#include "esp_log.h" 
#include "esp_event.h"
#include "esp_sntp.h"
#include "mqtt_client.h"
#include "esp_tls.h"
#include <sys/param.h>
#include "cJSON.h"
#include <map>
#include <functional>
#include <string>
#include "IIoTClient.h"
#include "AzureMqttIoTClient.h"

static const char *TAG = "AzureMqttIoTClient";

namespace AzureEventGrid
{
    /*static*/ IIoTClient* IIoTClient::Initialize(const IoTClientConfig& mqttCfg, IIoTClient::DesiredPropertyCallback_t callback,
            IIoTClient::CommandCallback_t commandCallback)
    {
        ESP_LOGI(TAG, "Initializing MQTT Client");
        static MqttIoTClient client(mqttCfg, callback, commandCallback);
        return &client;
    }

    MqttIoTClient::MqttIoTClient(const IoTClientConfig& iotClientConfig, IIoTClient::DesiredPropertyCallback_t desiredPropertyCallback, IIoTClient::CommandCallback_t commandCallback) :
     _clientId(iotClientConfig.GetClientId()), _commandCallback(commandCallback), _desiredPropertyCallback(desiredPropertyCallback) 
    {
        auto clientPrefix = std::string("device/") + _clientId;
        _responsesTopic = clientPrefix + std::string("/responses");
        _commandsTopic = clientPrefix + std::string("/commands");
        _desiredPropertyTopic = clientPrefix + std::string("/twin/desired");
        _reportedPropertyTopic = clientPrefix + std::string("/twin/reported");
        _telemetryTopic = clientPrefix + std::string("/telemetry");

        obtain_time();
        
        ESP_LOGI(TAG, "Initializing MQTT client for device %s", _clientId.c_str());
        
        esp_mqtt_client_config_t mqttCfg = {};
        mqttCfg.broker.address.uri = iotClientConfig.GetBrokerUri();
        mqttCfg.credentials.client_id = iotClientConfig.GetClientId();
        mqttCfg.credentials.authentication.certificate  = iotClientConfig.GetClientCert();
        mqttCfg.credentials.authentication.certificate_len = iotClientConfig.GetClientCertLength();
        mqttCfg.credentials.authentication.key = iotClientConfig.GetClientKey();
        mqttCfg.credentials.authentication.key_len = iotClientConfig.GetClientKeyLength();
        mqttCfg.credentials.username = iotClientConfig.GetClientId();
        mqttCfg.broker.verification.certificate = iotClientConfig.GetBrokerCert();
        mqttCfg.broker.verification.certificate_len = iotClientConfig.GetBrokerCertLength();
        

        _client = esp_mqtt_client_init(&mqttCfg);

        if (_client == nullptr) 
        {
            ESP_LOGE(TAG, "Failed to initialize MQTT client");
            return;
        }
        
        ESP_LOGI(TAG, "MQTT client initialized");
        
        int result = esp_mqtt_client_register_event(_client, (esp_mqtt_event_id_t)ESP_EVENT_ANY_ID, MqttIoTClient::MqttEventHandler, this);
        if (result != ESP_OK) 
        {
            ESP_LOGE(TAG, "Failed to register MQTT event handler");
            return;
        }
        
        result = esp_mqtt_client_start(_client);
        if (result != ESP_OK)
        {
            ESP_LOGE(TAG, "Failed to start MQTT client");
            return;
        }

         ESP_LOGI(TAG, "[APP] Free memory: %" PRIu32 " bytes", esp_get_free_heap_size());
    }

    void MqttIoTClient::SendTelemetry(const std::string& telemetryData) 
    {
        ESP_LOGD(TAG, "Sending telemetry data: %s", telemetryData.c_str());
        int msg_id = esp_mqtt_client_publish(_client, _telemetryTopic.c_str(), telemetryData.c_str(), telemetryData.length(), 0, 0);
        if (msg_id == -1)
        {
            ESP_LOGE(TAG, "Failed to send telemetry data");
        }
    }

    bool MqttIoTClient::UpdateReportedProperties(const std::string& reportedProps) 
    {
        int msg_id = esp_mqtt_client_publish(_client, _reportedPropertyTopic.c_str() , reportedProps.c_str(), reportedProps.length(), 0, 0);
        if (msg_id == -1)
        {
            ESP_LOGE(TAG, "Failed to send reported properties");
            return false;
        }
        _reportedProperties[reportedProps] = reportedProps; // Store locally if needed
        return true;
    }

    /*static*/ void MqttIoTClient::MqttEventHandler(void* handler_args, esp_event_base_t base, int32_t event_id, void* event_data) 
    {
        MqttIoTClient *pThis = reinterpret_cast<MqttIoTClient *>(event_data);
        pThis->EventHandler(handler_args, base, event_id, event_data);
    }

    std::string MqttIoTClient::GetDesiredProperty(const std::string& property)
    {
        auto it = _desiredProperties.find(property);
        if (it != _desiredProperties.end()) 
        {
            return it->second;
        }
        return "";
    }

    std::string MqttIoTClient::GetReportedProperty(const std::string& property)
    {
        auto it = _reportedProperties.find(property);
        if (it != _reportedProperties.end()) 
        {
            return it->second;
        }
        return "";
    }

    void MqttIoTClient::EventHandler(void* handler_args, esp_event_base_t base, int32_t event_id, void* event_data) 
    {
        ESP_LOGD(TAG, "Event dispatched from event loop base=%s, event_id=%" PRIi32, base, event_id);
        esp_mqtt_event_handle_t event = static_cast<esp_mqtt_event_handle_t>(event_data);

        esp_mqtt_client_handle_t client = event->client;
        int msg_id;
        switch ((esp_mqtt_event_id_t)event_id) 
        {
            case MQTT_EVENT_CONNECTED:
                ESP_LOGI(TAG, "MQTT_EVENT_CONNECTED");
                
                msg_id = esp_mqtt_client_subscribe(client, _desiredPropertyTopic.c_str(), 0);
                ESP_LOGI(TAG, "sent subscribe twin/desired successful, msg_id=%d", msg_id);

                msg_id = esp_mqtt_client_subscribe(client, _commandsTopic.c_str(), 0);
                ESP_LOGI(TAG, "sent subscribe commands successful, msg_id=%d", msg_id);

                msg_id = esp_mqtt_client_subscribe(client, _responsesTopic.c_str(), 0);
                ESP_LOGI(TAG, "sent subscribe responses successful, msg_id=%d", msg_id);

                ESP_LOGI(TAG, "sent subscribe successful, msg_id=%d", msg_id);
                break;

            case MQTT_EVENT_DISCONNECTED:
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

        cJSON* root = cJSON_ParseWithLength(event->data, event->data_len);
        if (root == nullptr) 
        {
            ESP_LOGE(TAG, "Failed to parse JSON data");
            return;
        }

        // Check if it is a desired property update
        if (std::string(event->topic).find("twin/desired") != std::string::npos) 
        {
            cJSON* desired = cJSON_GetObjectItemCaseSensitive(root, "desired");
            if (desired != nullptr && cJSON_IsObject(desired)) 
            {
                cJSON* property = cJSON_GetObjectItemCaseSensitive(desired, "property");
                if (property != nullptr && cJSON_IsString(property)) 
                {
                    std::string propertyName = property->valuestring;
                    std::string propertyValue = ""; // Retrieve the value based on your implementation
                    OnDesiredPropertyUpdate(propertyName, propertyValue);
                }
            }
        }

        // Check if it is a command
        else if (std::string(event->topic).find("commands") != std::string::npos) 
        {
            cJSON* methodName = cJSON_GetObjectItemCaseSensitive(root, "methodName");
            cJSON* payload = cJSON_GetObjectItemCaseSensitive(root, "payload");
            if (methodName != NULL && cJSON_IsString(methodName) && payload != NULL && cJSON_IsObject(payload)) 
            {
                std::string commandName = methodName->valuestring;
                std::string commandPayload = cJSON_Print(payload); // Retrieve the payload based on your implementation

                if (!_commandCallback) 
                {
                    std::string response = "{\"status\": 500, \"payload\": \"No command callback registered\"}";
                    int msg_id = esp_mqtt_client_publish(client, _responsesTopic.c_str(), response.c_str(), response.length(), 0, 0);
                    if (msg_id == -1) 
                    {
                        ESP_LOGE(TAG, "Failed to send command error response");
                    }
                    ESP_LOGE(TAG, "No command callback registered");
                } 
                else 
                {
                    std::string result = _commandCallback(this, commandName, commandPayload);
                    if (result.length() > 0) 
                    {
                        std::string response = "{\"status\": 200, \"payload\": " + result + "}";
                        int msg_id = esp_mqtt_client_publish(client, _responsesTopic.c_str(), response.c_str(), response.length(), 0, 0);
                        if (msg_id == -1) 
                        {
                            ESP_LOGE(TAG, "Failed to send command response");
                        }
                    }
                }
            }
        }

        // Check if it is a response
        else if (std::string(event->topic).find("responses") != std::string::npos) 
        {
            // Log the response
            ESP_LOGI(TAG, "Received response: %.*s", event->data_len, event->data);
        }

        cJSON_Delete(root);
    }

    void MqttIoTClient::OnDesiredPropertyUpdate(const std::string& propertyName, const std::string& propertyValue) 
    {
        ESP_LOGD(TAG, "Desired property update received: %s=%s", propertyName.c_str(), propertyValue.c_str());
        if(_desiredPropertyCallback)
        {
            _desiredPropertyCallback(this, propertyName, propertyValue);
        }
        _desiredProperties[propertyName] = propertyValue; // Store locally if needed
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