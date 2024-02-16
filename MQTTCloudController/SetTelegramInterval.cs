using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.WebJobs.Extensions.OpenApi.Core.Attributes;
using Microsoft.Extensions.Logging;
using Microsoft.OpenApi.Models;

namespace MQTTCloudController
{
    // ReSharper disable once ClassNeverInstantiated.Global
    // ReSharper disable InconsistentNaming
    public class SetTelegramInterval(ILogger<SetTelegramInterval> _logger, IMQTTSender _mqttSender)
    {
        [Function("SetTelegramInterval")]
        [OpenApiOperation(operationId: "SetTelegramInterval", tags: ["Device Management"])]
        [OpenApiParameter(name: "deviceName", In = ParameterLocation.Path, Required = true, Type = typeof(string),
            Description = "The name of the device")]
        [OpenApiParameter(name: "interval", In = ParameterLocation.Query, Required = true, Type = typeof(int),
            Description = "the time in seconds between the device temperature telemetry report")]
        public async Task<IActionResult> RunAsync(
            [HttpTrigger(AuthorizationLevel.Function, "post",
                Route = "device/{deviceName}/configuration/telegramInterval")]
            HttpRequest req,
            string deviceName, [FromQuery] int interval)
        {
            if (interval < 0)
            {
                return new BadRequestObjectResult("Interval must be a positive number");
            }

            if (interval > 3600)
            {
                return new BadRequestObjectResult("Interval must be less than 3600 seconds");
            }

            // Connect to the MQTT broker
            var result = await _mqttSender.ConnectAsync();

            if (result is BadRequestResult)
            {
                _logger.LogError("Error connecting to the MQTT broker");
                return result;
            }


            // Send a command to the device 
            var desiredPropertyTelemetryIntervalTopic = $"device/{deviceName}/twin/desired/delayBetweenTelemetry";
            

            result = await _mqttSender.PublishAsync(desiredPropertyTelemetryIntervalTopic, interval.ToString());
            if (result is BadRequestResult)
            {
                _logger.LogError("Error sending command to device");
                return result;
            }

            // Disconnect the client
            await _mqttSender.DisconnectAsync();

            return new OkResult();
        }
        
    }
}
