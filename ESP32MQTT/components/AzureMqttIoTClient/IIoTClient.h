#pragma once
#include <string>
#include "IoTClientConfig.h"
#include <functional>

namespace AzureEventGrid
{
    class IIoTClient 
    {
    public:
        using CommandCallback_t = std::function<std::string(IIoTClient *pClient, const std::string& name, const std::string& payload)>;
        using DesiredPropertyCallback_t = std::function<void(IIoTClient *pClient, const std::string& property, const std::string& value)>;

        IIoTClient() = default;
        static IIoTClient* Initialize(const IoTClientConfig& mqttCfg, DesiredPropertyCallback_t callback,
            CommandCallback_t commandCallback);

        virtual void SendTelemetry(const std::string& telemetryData) = 0;

        virtual bool UpdateReportedProperties(const std::string& reportedProps) = 0;

        virtual std::string GetDesiredProperty(const std::string& property) = 0;
        virtual std::string GetReportedProperty(const std::string& property) = 0;

        IIoTClient(const IIoTClient&) = delete;
        IIoTClient& operator=(const IIoTClient&) = delete;

        virtual ~IIoTClient() = default;
    };
}