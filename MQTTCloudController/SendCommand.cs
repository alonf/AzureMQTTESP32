using Azure.Core;
using Azure.Identity;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using MQTTnet;
using MQTTnet.Client;
using System.Text;
using Microsoft.Azure.WebJobs.Extensions.OpenApi.Core.Attributes;
using Microsoft.Extensions.Configuration;
using Microsoft.OpenApi.Models;
using MQTTnet.Formatter;
using MQTTnet.Protocol;
using System.Net.Mime;
using System.Web.Http;

#error todo, add jwt permission to the function app in the event grid namespace both in the cloud and the local script for the service principle
namespace MQTTCloudController
{
    // ReSharper disable InconsistentNaming
    // ReSharper disable once ClassNeverInstantiated.Global
    public class SendCommand(ILogger<SendCommand> _logger, IConfiguration _configuration)
    {
        // ReSharper disable once NotAccessedField.Local
        private static Timer? _refreshTokenTime;

        [Function("SendCommand")]
        [OpenApiOperation(operationId: "SendCommand", tags: new[] { "Device Management" })]
        [OpenApiParameter(name: "deviceName", In = ParameterLocation.Path, Required = true, Type = typeof(string),
            Description = "The name of the device")]
        [OpenApiParameter(name: "commandName", In = ParameterLocation.Path, Required = true, Type = typeof(string),
            Description = "The name of the command to send to the device")]
        [OpenApiParameter(name: "isOn", In = ParameterLocation.Query, Required = true, Type = typeof(bool),
            Description = "Turn the device on (true) or off (false)")]
        public async Task<IActionResult> RunAsync([HttpTrigger(AuthorizationLevel.Function,  "post", Route = "device/{deviceName}/command/{commandName}")] 
            HttpRequest req, string deviceName, string commandName, [FromQuery] bool isOn)
        {
            _logger.LogInformation("C# HTTP trigger function processed a request.");

            try
            {
                var mqttBrokerUrl = _configuration["MqttBrokerUrl"] ?? throw new ArgumentException("MqttBrokerUrl");
                var mqttBrokerPortText =
                    _configuration["MqttBrokerPort"] ?? throw new ArgumentException("MqttBrokerPort");

                var mqttBrokerPort = int.Parse(mqttBrokerPortText);

                var factory = new MqttFactory();
                var mqttClient = factory.CreateMqttClient();


                var options = new MqttClientOptionsBuilder()
                    .WithProtocolVersion(MqttProtocolVersion.V500)
                    .WithTcpServer(mqttBrokerUrl, mqttBrokerPort)
                    .WithTlsOptions(a => a.UseTls())
                    .WithAuthentication("OAUTH2-JWT", GetToken())
                    .Build();

                // Connect to the MQTT broker
                await mqttClient.ConnectAsync(options, CancellationToken.None);

                //handle token expiration
                // ReSharper disable once AsyncVoidLambda
                _refreshTokenTime = new Timer(async _ =>
                {
                    if (!mqttClient.IsConnected)
                        return;

                    await mqttClient.SendExtendedAuthenticationExchangeDataAsync(
                        new MqttExtendedAuthenticationExchangeData()
                        {
                            AuthenticationData = GetToken(),
                            ReasonCode = MqttAuthenticateReasonCode.ReAuthenticate
                        });
                }, null, 0, (int)TimeSpan.FromHours(1).TotalMilliseconds);



                // Send a command to the device 
                var commandTopic = $"device/{deviceName}/commands/{commandName}";
                var commandPayload = isOn
                    ? """
                      {
                         "state": "on"
                      }
                      """u8.ToArray()
                    : """
                      {
                          "state": "off"
                      }
                      """u8.ToArray();

                var commandMessage = new MqttApplicationMessageBuilder()
                    .WithTopic(commandTopic)
                    .WithPayload(commandPayload)
                    .WithQualityOfServiceLevel(MqttQualityOfServiceLevel.AtMostOnce)
                    .Build();
                await mqttClient.PublishAsync(commandMessage, CancellationToken.None);

                // Disconnect the client
                await mqttClient.DisconnectAsync();

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

       
        static byte[] GetToken()
        {
            var azureDefaultCredential = new DefaultAzureCredential();

            AccessToken jwt =
                azureDefaultCredential.GetToken(new TokenRequestContext(["https://eventgrid.azure.net/.default"]));
            return Encoding.UTF8.GetBytes(jwt.Token);
        }
    }
}
