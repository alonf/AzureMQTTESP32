using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Azure.WebJobs.Extensions.OpenApi.Core.Attributes;
using Microsoft.OpenApi.Models;
using System.Web.Http;

namespace MQTTCloudController;

// ReSharper disable InconsistentNaming
// ReSharper disable once ClassNeverInstantiated.Global
public class SendCommand(ILogger<SendCommand> _logger, IMQTTSender _mqttSender)
{
    [Function("SendCommand")]
    [OpenApiOperation(operationId: "SendCommand", tags: ["Device Management"])]
    [OpenApiParameter(name: "deviceName", In = ParameterLocation.Path, Required = true, Type = typeof(string),
        Description = "The name of the device")]
    [OpenApiParameter(name: "commandName", In = ParameterLocation.Path, Required = true, Type = typeof(string),
        Description = "The name of the command to send to the device")]
    [OpenApiParameter(name: "isOn", In = ParameterLocation.Query, Required = true, Type = typeof(bool),
        Description = "Turn the device on (true) or off (false)")]
    public async Task<IActionResult> RunAsync(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "device/{deviceName}/command/{commandName}")]
        HttpRequest req, string deviceName, string commandName, [FromQuery] bool isOn)
    {
        _logger.LogInformation("C# HTTP trigger function processed a request.");

        try
        {

            if (string.IsNullOrEmpty(deviceName))
            {
                return new BadRequestObjectResult("Device name is required");
            }

            if (string.IsNullOrEmpty(commandName))
            {
                return new BadRequestObjectResult("Command name is required");
            }

            // Connect to the MQTT broker
            var result = await _mqttSender.ConnectAsync();

            if (result is BadRequestResult)
            {
                _logger.LogError("Error connecting to the MQTT broker");
                return result;
            }


            // Send a command to the device 
            var commandTopic = $"device/{deviceName}/commands/{commandName}";
            var commandPayload = isOn
                ? """
                  {
                     "state": "on"
                  }
                  """
                : """
                  {
                      "state": "off"
                  }
                  """;


            result = await _mqttSender.PublishAsync(commandTopic, commandPayload);
            if (result is BadRequestResult)
            {
                _logger.LogError("Error sending command to device");
                return result;
            }

            // Disconnect the client
            await _mqttSender.DisconnectAsync();


            return new OkResult();
        }
        catch (MQTTnet.Exceptions.MqttCommunicationException ex)
        {
            _logger.LogError(ex, "Error communicating with the MQTT broker");
            return new BadRequestErrorMessageResult(ex.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error sending command to device");
            return new ObjectResult(ex.Message)
            {
                StatusCode = StatusCodes.Status500InternalServerError
            };
        }
    }
}

