#include "esp_log.h" 
#include "esp_event.h"
#include "esp_sntp.h"
#include "mqtt_client.h"
#include "esp_tls.h"
#include <sys/param.h>
#include "cJSON.h"
#include <map>
#include <functional>
#include <memory>
#include <string>
#include <exception>
#include "IIoTClient.h"
#include "AzureMqttIoTClient.h"
#include <mbedtls/sha256.h>  // Include this for SHA-256 hash function

static const char *TAG = "AzureMqttIoTClient";

namespace AzureEventGrid
{
    /*static*/ MqttIoTClient *MqttIoTClient::_pThis;
    
    /*static*/ IIoTClient* IIoTClient::Initialize(const IoTClientConfig& mqttCfg, IIoTClient::DesiredPropertyCallback_t callback,
            IIoTClient::CommandCallback_t commandCallback)
    {
        ESP_LOGI(TAG, "Initializing MQTT Client");
        static MqttIoTClient client(mqttCfg, callback, commandCallback);
        MqttIoTClient::_pThis = &client;
        return &client;
    }

void log_sha256_hash(const unsigned char* data, size_t data_len, const char* label) {
    unsigned char hash[32];
    char hashString[65];  // 64 chars for the hash, 1 for null-terminator
    mbedtls_sha256(data, data_len, hash, 0);  // Compute SHA-256 hash

    // Convert the hash to a hexadecimal string
    for (int i = 0; i < 32; i++) {
        sprintf(&hashString[i * 2], "%02x", hash[i]);
    }

    // Log the hash with the given label
    ESP_LOGI(TAG, "%s SHA-256: %s", label, hashString);
}


    MqttIoTClient::MqttIoTClient(const IoTClientConfig& iotClientConfig, IIoTClient::DesiredPropertyCallback_t desiredPropertyCallback, IIoTClient::CommandCallback_t commandCallback) :
     _clientId(iotClientConfig.GetClientId()), _commandCallback(commandCallback), _desiredPropertyCallback(desiredPropertyCallback) 
    {
        auto clientPrefix = std::string("device/") + _clientId;
        _responsesTopic = clientPrefix + std::string("/responses/");
        _commandsTopic = clientPrefix + std::string("/commands/");
        _desiredPropertyTopic = clientPrefix + std::string("/twin/desired/");
        _reportedPropertyTopic = clientPrefix + std::string("/twin/reported/");
        _telemetryTopic = clientPrefix + std::string("/telemetry/");

        _messageHandlers[0] = std::make_unique<CommandHandler>(this);
        _messageHandlers[1] = std::make_unique<DesiredPropertyHandler>(this);

        ESP_LOGI(TAG, "this=%x\n", (unsigned int)this);
        obtain_time();
        
        ESP_LOGI(TAG, "Initializing MQTT client for device %s", _clientId.c_str());
        esp_mqtt_client_config_t mqttCfg = {};
        mqttCfg.broker.address.uri = iotClientConfig.GetBrokerUri();
        ESP_LOGI(TAG, "Broker URI: %s", mqttCfg.broker.address.uri);

        mqttCfg.credentials.client_id = iotClientConfig.GetClientId();
        ESP_LOGI(TAG, "Client ID: %s", mqttCfg.credentials.client_id);

         // Log client certificate hash
        const unsigned char* client_cert = (const unsigned char*)iotClientConfig.GetClientCert();
        const size_t client_cert_len = iotClientConfig.GetClientCertLength();
        log_sha256_hash(client_cert, client_cert_len, "Client Certificate");
        mqttCfg.credentials.authentication.certificate = iotClientConfig.GetClientCert();
        mqttCfg.credentials.authentication.certificate_len = iotClientConfig.GetClientCertLength();

        // Log client key hash
        const unsigned char* client_key = (const unsigned char*)iotClientConfig.GetClientKey();
        const size_t client_key_len = iotClientConfig.GetClientKeyLength();
        log_sha256_hash(client_key, client_key_len, "Client Key");
        mqttCfg.credentials.authentication.key = iotClientConfig.GetClientKey();
        mqttCfg.credentials.authentication.key_len = iotClientConfig.GetClientKeyLength();

        // Log username
        mqttCfg.credentials.username = iotClientConfig.GetClientId();
        ESP_LOGI(TAG, "Username: %s", mqttCfg.credentials.username);

        // Log broker certificate hash
        const unsigned char* broker_cert = (const unsigned char*)iotClientConfig.GetBrokerCert();
        const size_t broker_cert_len = iotClientConfig.GetBrokerCertLength();
        log_sha256_hash(broker_cert, broker_cert_len, "Broker Certificate");
        mqttCfg.broker.verification.certificate = iotClientConfig.GetBrokerCert();
        mqttCfg.broker.verification.certificate_len = iotClientConfig.GetBrokerCertLength();

        _client = esp_mqtt_client_init(&mqttCfg);

        if (_client == nullptr) 
        {
            ESP_LOGE(TAG, "Failed to initialize MQTT client");
            return;
        }
        
        ESP_LOGI(TAG, "MQTT client initialized");
        
        int result = esp_mqtt_client_register_event(_client, (esp_mqtt_event_id_t)ESP_EVENT_ANY_ID, MqttIoTClient::MqttEventHandler, nullptr);
        if (result != ESP_OK) 
        {
            ESP_LOGE(TAG, "Failed to register MQTT event handler");
            return;
        }
        ESP_LOGI(TAG, "MQTT client registered to MQTT event handler");
        
        result = esp_mqtt_client_start(_client);
        if (result != ESP_OK)
        {
            ESP_LOGE(TAG, "Failed to start MQTT client");
            return;
        }

         ESP_LOGI(TAG, "[APP] Free memory: %" PRIu32 " bytes", esp_get_free_heap_size());
    }

    MqttIoTClient::~MqttIoTClient() 
    {
        if (_client != nullptr) 
        {
            esp_mqtt_client_stop(_client);
            esp_mqtt_client_destroy(_client);
        }
    }

    void MqttIoTClient::SendTelemetry(const std::string& telemetrySubTopicName, const std::string& telemetryData) 
    {
        //first check if the client is connected
        if (IsConnected() == false) 
        {
            ESP_LOGE(TAG, "MQTT client is not connected");
            return;
        }

        ESP_LOGI(TAG, "Sending telemetry of sub topic: %s, data: %s", telemetrySubTopicName.c_str(), telemetryData.c_str());
        auto topic = _telemetryTopic + telemetrySubTopicName;

        int msg_id = esp_mqtt_client_publish(_client, topic.c_str(), telemetryData.c_str(), telemetryData.length(), MQTT_QOS, 0);
        if (msg_id == -1)
        {
            ESP_LOGE(TAG, "Failed to send telemetry data");
        }
    }

    bool MqttIoTClient::UpdateReportedProperties(const std::string& reportedPropertyName, const std::string& reportedPropertyValue) 
    {
        auto topic = _reportedPropertyTopic + reportedPropertyName;
        int msg_id = esp_mqtt_client_publish(_client, topic.c_str() , reportedPropertyValue.c_str(), reportedPropertyValue.length(), MQTT_QOS, 0);
        if (msg_id == -1)
        {
            ESP_LOGE(TAG, "Failed to send reported properties");
            return false;
        }
        _reportedProperties[reportedPropertyName] = reportedPropertyValue; // Store locally if needed
        return true;
    }

    /*static*/ void MqttIoTClient::MqttEventHandler(void* handler_args, esp_event_base_t base, int32_t event_id, void* event_data) 
    {
        ESP_LOGI(TAG, "MqttEventHandler");
        _pThis->EventHandler(handler_args, base, event_id, event_data);
    }

    std::string MqttIoTClient::GetDesiredProperty(const std::string& propertyName)
    {
        auto it = _desiredProperties.find(propertyName);
        if (it != _desiredProperties.end()) 
        {
            return it->second;
        }
        return "";
    }

    std::string MqttIoTClient::GetReportedProperty(const std::string& propertyName)
    {
        auto it = _reportedProperties.find(propertyName);
        if (it != _reportedProperties.end()) 
        {
            return it->second;
        }
        return "";
    }

    void MqttIoTClient::EventHandler(void* handler_args, esp_event_base_t base, int32_t event_id, void* event_data) 
    {
        ESP_LOGI(TAG, "Event dispatched from event loop base=%s, event_id=%" PRIi32, base, event_id);
        esp_mqtt_event_handle_t event = static_cast<esp_mqtt_event_handle_t>(event_data);

        esp_mqtt_client_handle_t client = event->client;
        int msg_id;
        switch ((esp_mqtt_event_id_t)event_id) 
        {
            case MQTT_EVENT_CONNECTED:
            {
                _isConnected = true;
                ESP_LOGI(TAG, "_desiredPropertyTopic empty: %d", _desiredPropertyTopic.empty() == false);
                ESP_LOGI(TAG, "Topic: %s\n", _desiredPropertyTopic.c_str());
                
                ESP_LOGI(TAG, "Subscribing to topics");

                auto desiredPropertyTopic = _desiredPropertyTopic + "#";
                msg_id = esp_mqtt_client_subscribe(client, desiredPropertyTopic.c_str(), MQTT_QOS);
                ESP_LOGI(TAG, "sent subscribe %s, msg_id=%d", desiredPropertyTopic.c_str(), msg_id);

                auto commandsTopic = _commandsTopic + "#";
                msg_id = esp_mqtt_client_subscribe(client, commandsTopic.c_str(), MQTT_QOS);
                ESP_LOGI(TAG, "sent subscribe %s, msg_id=%d", commandsTopic.c_str(), msg_id);

                auto responsesTopic = _responsesTopic + "#";
                msg_id = esp_mqtt_client_subscribe(client, responsesTopic.c_str(), MQTT_QOS);
                ESP_LOGI(TAG, "sent subscribe %s, msg_id=%d", responsesTopic.c_str(), msg_id);

                ESP_LOGI(TAG, "sent subscribe successful, msg_id=%d", msg_id);
            }
            break;

            case MQTT_EVENT_DISCONNECTED:
                _isConnected = false;
                ESP_LOGI(TAG, "MQTT_EVENT_DISCONNECTED");
                break;

            case MQTT_EVENT_SUBSCRIBED:
                ESP_LOGI(TAG, "MQTT_EVENT_SUBSCRIBED, msg_id=%d", event->msg_id);
                break;

            case MQTT_EVENT_UNSUBSCRIBED:
                ESP_LOGI(TAG, "MQTT_EVENT_UNSUBSCRIBED, msg_id=%d", event->msg_id);
                break;

            case MQTT_EVENT_PUBLISHED:
                ESP_LOGI(TAG, "MQTT_EVENT_PUBLISHED, msg_id=%d", event->msg_id);
                break;

            case MQTT_EVENT_DATA:
                ProcessMqttEventData(client, event);
                break;  
                
            case MQTT_EVENT_ERROR:
                ESP_LOGI(TAG, "MQTT_EVENT_ERROR");
                if (event->error_handle->error_type == MQTT_ERROR_TYPE_TCP_TRANSPORT) 
                {
                    ESP_LOGI(TAG, "Last error code reported from esp-tls: 0x%x", event->error_handle->esp_tls_last_esp_err);
                    ESP_LOGI(TAG, "Last tls stack error number: 0x%x", event->error_handle->esp_tls_stack_err);
                    ESP_LOGI(TAG, "Last captured errno : %d (%s)",  event->error_handle->esp_transport_sock_errno,
                            strerror(event->error_handle->esp_transport_sock_errno));
                }
                else if (event->error_handle->error_type == MQTT_ERROR_TYPE_CONNECTION_REFUSED) 
                {
                    ESP_LOGI(TAG, "Connection refused error: 0x%x", event->error_handle->connect_return_code);
                }
                else
                {
                    ESP_LOGW(TAG, "Unknown error type: 0x%x", event->error_handle->error_type);
                }
                break;

            default:
                ESP_LOGI(TAG, "Other event id:%d", event->event_id);
                break;
        }
    }

    void MqttIoTClient::ProcessMqttEventData(esp_mqtt_client_handle_t client, esp_mqtt_event_handle_t event) 
    {
        ESP_LOGI(TAG, "MQTT_EVENT_DATA");
        printf("TOPIC=%.*s\r\n", event->topic_len, event->topic);
        printf("DATA=%.*s\r\n", event->data_len, event->data);

        std::string topic(event->topic, event->topic_len);
        std::string payload(event->data, event->data_len);

        for (auto& handler : _messageHandlers) 
        {
            if (handler->IsResponsibleFor(topic)) 
            {
                handler->HandleMessage(topic, payload);
                break;
            }
        }
    }


    void MqttIoTClient::CommandHandler::HandleMessage(const std::string& topic, const std::string& payload)
    {
        ESP_LOGI(TAG, "Received command: %s with payload: %s", topic.c_str(), payload.c_str());

        //the command name is the last part of the topic
        auto pos = topic.find_last_of('/');
        if (pos == std::string::npos)
        {
            ESP_LOGE(TAG, "Invalid command topic: %s", topic.c_str());
            return;
        }
        
        std::string commandName = topic.substr(pos + 1);
        std::string result = _mqttIoTClient.ActivateCommand(commandName, payload);
        if (result.length() > 0)
        {
            std::string response = "{\"status\": 200, \"payload\": " + result + "}";
            int msg_id = _mqttIoTClient.PublishResponse(commandName, response);
            if (msg_id == -1)
            {
                ESP_LOGE(TAG, "Failed to send command response");
            }
        }
    }

    void MqttIoTClient::OnDesiredPropertyUpdate(const std::string& propertyName, const std::string& propertyValue) 
    {
        ESP_LOGI(TAG, "Updating desired property: %s = %s", propertyName.c_str(), propertyValue.c_str());
        // Custom logic to handle the desired property update
        _desiredProperties[propertyName] = propertyValue;
        // Invoke any callback if necessary
        if (_desiredPropertyCallback) 
        {
            try
            {
                _desiredPropertyCallback(this, propertyName, propertyValue);
            }
            catch (const std::exception& e)
            {
                ESP_LOGE(TAG, "Exception while processing desired property update: %s", e.what());
            }
            catch (...)
            {
                ESP_LOGE(TAG, "Unknown exception while processing desired property update");
            }
        }
    }

    std::string MqttIoTClient::ActivateCommand(const std::string& commandName, const std::string& commandPayload) 
    {
        ESP_LOGI(TAG, "Activating command: %s with payload: %s", commandName.c_str(), commandPayload.c_str());

        // Check if a command callback is registered
        if (!_commandCallback) 
        {
            ESP_LOGW(TAG, "No command callback registered for %s", commandName.c_str());
            // Return a response indicating that no callback is registered for handling commands
            return "{\"error\": \"No command callback registered\"}";
        }
    
        // Call the registered command callback function with the command name and payload
        try 
        {
            std::string result = _commandCallback(this, commandName, commandPayload);

            // Log and return the result of the command execution
            ESP_LOGI(TAG, "Command %s processed with result: %s", commandName.c_str(), result.c_str());
            return result;
        } 
        catch (const std::exception& e) 
        {
            // Log any exceptions thrown by the command callback
            ESP_LOGE(TAG, "Exception while executing command %s: %s", commandName.c_str(), e.what());
            return "{\"error\": \"Exception occurred while processing command\"}";
        }
        catch (...) 
        {
            // Log any unknown exceptions thrown by the command callback
            ESP_LOGE(TAG, "Unknown exception while executing command %s", commandName.c_str());
            return "{\"error\": \"Unknown exception occurred while processing command\"}";
        }
    }

    bool MqttIoTClient::PublishResponse(const std::string& subTopic, const std::string& response) 
    {
        //first check if the client is connected
        if (IsConnected() == false)
        {
            ESP_LOGE(TAG, "MQTT client is not connected");
            return false;
        }

        auto responseTopic = _responsesTopic + subTopic;

        ESP_LOGI(TAG, "Publishing response to %s: %s", responseTopic.c_str(), response.c_str());
        int msg_id = esp_mqtt_client_publish(_client, responseTopic.c_str(), response.c_str(), response.length(), MQTT_QOS, 0);
        if (msg_id == -1) 
        {
            ESP_LOGE(TAG, "Failed to publish response");
            return false;
        }
        return true;
    }


    void MqttIoTClient::DesiredPropertyHandler::HandleMessage(const std::string& topic, const std::string& payload)
    {
        ESP_LOGI(TAG, "Received desired property update: %s with payload: %s", topic.c_str(), payload.c_str());

        //the property name is the last part of the topic
        auto pos = topic.find_last_of('/');
        if (pos == std::string::npos)
        {
            ESP_LOGE(TAG, "Invalid desired property topic: %s", topic.c_str());
            return;
        }
        
        std::string propertyName = topic.substr(pos + 1);
        _mqttIoTClient.OnDesiredPropertyUpdate(propertyName, payload);
    }

    /*static*/ void MqttIoTClient::obtain_time(void)
    {
        // Initialize the SNTP service
        esp_sntp_setoperatingmode(SNTP_OPMODE_POLL);
        esp_sntp_setservername(0, "pool.ntp.org"); // Use the "pool.ntp.org" server
        esp_sntp_init();

        // Wait for time to be set
        time_t now = 0;
        struct tm timeinfo =
                {
                        0, // tm_sec
                        0, // tm_min
                        0, // tm_hour
                        0, // tm_mday
                        0, // tm_mon
                        0, // tm_year
                        0, // tm_wday
                        0, // tm_yday
                        0  // tm_isdst
                };

        int retry = 0;
        const int retry_count = 10;
        while (sntp_get_sync_status() == SNTP_SYNC_STATUS_RESET && ++retry < retry_count) {
            ESP_LOGI(TAG, "Waiting for system time to be set... (%d/%d)", retry, retry_count);
            vTaskDelay(2000 / portTICK_PERIOD_MS);
        }
        time(&now);
        localtime_r(&now, &timeinfo);
    }

}