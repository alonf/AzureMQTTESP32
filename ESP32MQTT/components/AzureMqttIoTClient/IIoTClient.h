#pragma once
#include <string>
#include "IoTClientConfig.h"
#include <functional>

namespace AzureEventGrid
{
    class IIoTClient 
    {
    public:
        using CommandCallback_t = std::function<std::string(IIoTClient *pClient, const std::string& commandName, const std::string& payload)>;
        using DesiredPropertyCallback_t = std::function<void(IIoTClient *pClient, const std::string& propertyName, const std::string& propertyValue)>;

        IIoTClient() = default;
        static IIoTClient* Initialize(const IoTClientConfig& mqttCfg, DesiredPropertyCallback_t callback,
            CommandCallback_t commandCallback);

        virtual void SendTelemetry(const std::string& telemetrySubTopicName, const std::string& telemetryData) = 0;

        virtual bool UpdateReportedProperties(const std::string& reportedPropertyName, const std::string& reportedPropertyValue) = 0;
        virtual bool IsConnected() const = 0;
        virtual std::string GetDesiredProperty(const std::string& propertyName) = 0;
        virtual std::string GetReportedProperty(const std::string& propertyName) = 0;

        IIoTClient(const IIoTClient&) = delete;
        IIoTClient& operator=(const IIoTClient&) = delete;

        virtual ~IIoTClient() = default;
    };
}