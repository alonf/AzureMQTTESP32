using System.Text;
using System.Web.Http;
using Azure.Core;
using Azure.Identity;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using MQTTnet;
using MQTTnet.Client;
using MQTTnet.Formatter;
using MQTTnet.Protocol;

namespace MQTTCloudController;

public class MQTTSender : IMQTTSender
{
    private readonly IMqttClient _mqttClient;
    private readonly ILogger<MQTTSender> _logger;
    private readonly MqttClientOptions _options;
    // ReSharper disable once NotAccessedField.Local
    private Timer? _refreshTokenTime;

    public MQTTSender(IConfiguration configuration, ILogger<MQTTSender> logger)
    {
        _logger = logger;
        
        try
        {
            var mqttBrokerUrl = configuration["MqttBrokerUrl"] ?? throw new ArgumentException("MqttBrokerUrl");
            var mqttBrokerPortText =
                configuration["MqttBrokerPort"] ?? throw new ArgumentException("MqttBrokerPort");

            var mqttBrokerPort = int.Parse(mqttBrokerPortText);

            var factory = new MqttFactory();
            _mqttClient = factory.CreateMqttClient();


            _options = new MqttClientOptionsBuilder()
                .WithProtocolVersion(MqttProtocolVersion.V500)
                .WithTcpServer(mqttBrokerUrl, mqttBrokerPort)
                .WithTlsOptions(a => a.UseTls())
                .WithClientId("mqtt-cloud-controller-" + Guid.NewGuid()) //make sure concurrent functions run
                .WithAuthentication("OAUTH2-JWT", GetToken())
                .Build();
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error creating MQTT client");
            throw;
        }
    }

    public async Task<IActionResult> ConnectAsync()
    {
        try
        {
            if (_mqttClient.IsConnected)
            {
                _logger.LogInformation("Already connected to the MQTT broker");
                return new OkResult();
            }

            // Connect to the MQTT broker
            await _mqttClient.ConnectAsync(_options, CancellationToken.None);

            //handle token expiration
            // ReSharper disable once AsyncVoidLambda
            _refreshTokenTime = new Timer(async _ =>
            {
                try
                {

                    if (!_mqttClient.IsConnected)
                        return;

                    await _mqttClient.SendExtendedAuthenticationExchangeDataAsync(
                        new MqttExtendedAuthenticationExchangeData()
                        {
                            AuthenticationData = GetToken(),
                            ReasonCode = MqttAuthenticateReasonCode.ReAuthenticate
                        });
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error refreshing token");
                }
            }, null, (int)TimeSpan.FromHours(1).TotalMilliseconds, (int)TimeSpan.FromHours(1).TotalMilliseconds);
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
        return new OkResult();
    }

    public async Task<IActionResult> PublishAsync(string topic, string payload)
    {
        var utf8Payload = Encoding.UTF8.GetBytes(payload);

        var message = new MqttApplicationMessageBuilder()
            .WithTopic(topic)
            .WithPayload(utf8Payload)
            .WithQualityOfServiceLevel(MqttQualityOfServiceLevel.AtLeastOnce)
            .Build();

        var now = DateTime.Now;

        while (!_mqttClient.IsConnected)
        {
            if (DateTime.Now - now > TimeSpan.FromSeconds(10))
            {
                return new BadRequestResult();
            }
        }
        await _mqttClient.PublishAsync(message, CancellationToken.None);
        return new OkResult();
    }

    public async Task DisconnectAsync()
    {
        if (_refreshTokenTime != null) 
            await _refreshTokenTime.DisposeAsync();
        await _mqttClient.DisconnectAsync();
    }

    static byte[] GetToken()
    {
        var azureDefaultCredential = new DefaultAzureCredential();

        AccessToken jwt =
            azureDefaultCredential.GetToken(new TokenRequestContext(["https://eventgrid.azure.net/.default"]));
        return Encoding.UTF8.GetBytes(jwt.Token);
    }
}