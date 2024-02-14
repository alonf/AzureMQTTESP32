#pragma once
#include "IIoTClient.h"
namespace AzureEventGrid
{
    class MqttIoTClient : public IIoTClient
    {
        friend class IIoTClient;
    public:

        void SendTelemetry(const std::string& telemetryData) override;

        bool UpdateReportedProperties(const std::string& reportedProps) override;

        std::string GetDesiredProperty(const std::string& property) override;
        std::string GetReportedProperty(const std::string& property) override;

        MqttIoTClient(const MqttIoTClient&) = delete;
        MqttIoTClient& operator=(const MqttIoTClient&) = delete;

    private:
        MqttIoTClient(const IoTClientConfig& mqttCfg, 
            IIoTClient::DesiredPropertyCallback_t desiredPropertyCallback, IIoTClient::CommandCallback_t commandCallback);

        void EventHandler(void* handler_args, esp_event_base_t base, int32_t event_id, void* event_data);
        static void MqttEventHandler(void* handler_args, esp_event_base_t base, int32_t event_id, void* event_data) ;
        static void obtain_time(void);
        void OnDesiredPropertyUpdate(const std::string& propertyName, const std::string& propertyValue);
        void ProcessMqttEventData(esp_mqtt_client_handle_t client, esp_mqtt_event_handle_t event);
        static MqttIoTClient *_pThis; //singleton
       
        std::string _responsesTopic;
        std::string _commandsTopic;
        std::string _desiredPropertyTopic;
        std::string _reportedPropertyTopic;
        std::string _telemetryTopic;
        
        const std::string _clientId;
        IIoTClient::CommandCallback_t _commandCallback;
        IIoTClient::DesiredPropertyCallback_t _desiredPropertyCallback;
        
        esp_mqtt_client_handle_t _client;
        std::map<std::string, std::string> _desiredProperties;
        std::map<std::string, std::string> _reportedProperties;
    };
}