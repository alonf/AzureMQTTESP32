#include <map>
#include <functional>
#include <string>

namespace AzureEventGrid
{
    class MqttIoTClient 
    {
    public:
        using CommandCallback_t = std::function<std::string(MqttIoTClient *pClient, const std::string& command, const std::string& payload)>;
        using DesiredPropertyCallback_t = std::function<void(MqttIoTClient *pClient, const std::string& property, const std::string& value)>;

        static MqttIoTClient* MqttIoTClient::Initialize(const esp_mqtt_client_config_t& mqtt_cfg, DesiredPropertyCallback_t callback, 
            CommandCallback_t commandCallback);

        void SendTelemetry(const std::string& telemetryData);

        void UpdateReportedProperties(const std::string& reportedProps);

        std::string GetDesiredProperty(const std::string& property);
        std::string GetReportedProperty(const std::string& property);

        MqttIoTClient(const MqttIoTClient&) = delete;
        MqttIoTClient& operator=(const MqttIoTClient&) = delete;

    private:
        MqttIoTClient(const esp_mqtt_client_config_t& mqtt_cfg, DesiredPropertyCallback_t callback, 
            CommandCallback_t commandCallback);

        static void MqttIoTClient::obtain_time(void);
              
        static MqttIoTClient *_pThis; //singleton
       
        std::string _responseTopic;
        std::string _commandTopic;
        std::string _desiredPropertyTopic;
        std::string _reportedPropertyTopic;
        std::string _telemetryTopic;

        esp_mqtt_client_handle_t _client;
        CommandCallback_t _commandCallback;
        DesiredPropertyCallback_t _desiredPropertyCallback;
        std::map<std::string, std::string> _desiredProperties;
        std::map<std::string, std::string> _reportedProperties;

        static void MqttIoTClient::(void* handler_args, esp_event_base_t base, int32_t event_id, void* event_data);
    };
}