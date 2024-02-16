#pragma once
#include "IIoTClient.h"
namespace AzureEventGrid
{
    class MqttIoTClient : public IIoTClient
    {
        friend class IIoTClient;
    public:

        void SendTelemetry(const std::string& telemetrySubTopicName, const std::string& telemetryData) override;

        bool UpdateReportedProperties(const std::string& reportedPropertyName, const std::string& reportedPropertyValue) override;

        std::string GetDesiredProperty(const std::string& property) override;
        std::string GetReportedProperty(const std::string& property) override;

        bool IsConnected() const override
        {
            return _client != nullptr && _isConnected;
        }

        MqttIoTClient(const MqttIoTClient&) = delete;
        MqttIoTClient& operator=(const MqttIoTClient&) = delete;
        ~MqttIoTClient() override;

    private:
        friend class MessageHandler;
        friend class CommandHandler;
        friend class DesiredPropertyHandler;

        MqttIoTClient(const IoTClientConfig& mqttCfg, 
            IIoTClient::DesiredPropertyCallback_t desiredPropertyCallback, IIoTClient::CommandCallback_t commandCallback);

        void EventHandler(void* handler_args, esp_event_base_t base, int32_t event_id, void* event_data);
        static void MqttEventHandler(void* handler_args, esp_event_base_t base, int32_t event_id, void* event_data) ;
        static void obtain_time(void);
        void OnDesiredPropertyUpdate(const std::string& propertyName, const std::string& propertyValue);
        void ProcessMqttEventData(esp_mqtt_client_handle_t client, esp_mqtt_event_handle_t event);
        std::string ActivateCommand(const std::string& commandName, const std::string& commandPayload);
        bool PublishResponse(const std::string& subTopic, const std::string& response);
        void ProcessDesiredPropertyUpdate(const std::string& propertyName, const std::string& propertyValue);

        static MqttIoTClient *_pThis; //singleton

        const std::string& GetResponsesTopic() const
        {
            return _responsesTopic;
        }

        const std::string& GetCommandsTopic() const 
        {
            return _commandsTopic;
        }

        const std::string& GetDesiredPropertyTopic() const 
        {
            return _desiredPropertyTopic;
        }

        const std::string& GetReportedPropertyTopic() const 
        {
            return _reportedPropertyTopic;
        }

        const std::string& GetTelemetryTopic() const 
        {
            return _telemetryTopic;
        }

        
        std::string _responsesTopic;
        std::string _commandsTopic;
        std::string _desiredPropertyTopic;
        std::string _reportedPropertyTopic;
        std::string _telemetryTopic;
        bool _isConnected {};
        
        const std::string _clientId;
        IIoTClient::CommandCallback_t _commandCallback;
        IIoTClient::DesiredPropertyCallback_t _desiredPropertyCallback;
        
        esp_mqtt_client_handle_t _client;
        std::map<std::string, std::string> _desiredProperties;
        std::map<std::string, std::string> _reportedProperties;

        static const int MQTT_QOS = 1;



       
        class MessageHandler 
        {
        protected:
            MqttIoTClient &_mqttIoTClient;

        public:
            MessageHandler(MqttIoTClient* pClient) : _mqttIoTClient(*pClient) {}
            virtual ~MessageHandler() = default;

            // Provide a method to get the topic string from derived classes
            virtual const std::string& GetTopicPrefix() const = 0;

            // Implement common logic for checking responsibility based on the topic prefix
            virtual bool IsResponsibleFor(const std::string& topic) const 
            {
                return topic.find(GetTopicPrefix()) == 0;
            }

            virtual void HandleMessage(const std::string& topic, const std::string& payload) = 0;
        };

        class CommandHandler : public MessageHandler 
        {
        public:
            using MessageHandler::MessageHandler;
            
            const std::string& GetTopicPrefix() const override 
            {
                return _mqttIoTClient.GetCommandsTopic();
            }

            void HandleMessage(const std::string& topic, const std::string& payload) override;
        };

        class DesiredPropertyHandler : public MessageHandler 
        {
        public:
            using MessageHandler::MessageHandler;
            
            const std::string& GetTopicPrefix() const override 
            {
                return _mqttIoTClient.GetDesiredPropertyTopic();
            }

            void HandleMessage(const std::string& topic, const std::string& payload) override;
        };

        std::array<std::unique_ptr<MessageHandler>, 2> _messageHandlers;
    };
}