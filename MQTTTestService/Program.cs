using System.Text;
using Azure.Core;
using Azure.Identity;
using MQTTnet;
using MQTTnet.Client;
using MQTTnet.Formatter;
using MQTTnet.Protocol;

namespace MQTTTestService;

public static class Program
{
    //set timer sa static variable to keep it alive
    // ReSharper disable once NotAccessedField.Local
    private static Timer? _refreshTokenTime;

    static async Task Main(string[] args)
    {

        var factory = new MqttFactory();
        var mqttClient = factory.CreateMqttClient();
        //var broker = "testesp32ns.uaenorth-1.ts.eventgrid.azure.net";
        var broker = "mqttdemo.uaenorth-1.ts.eventgrid.azure.net";
        var port = 8883;

        
        var options = new MqttClientOptionsBuilder()
            .WithProtocolVersion(MqttProtocolVersion.V500)
            .WithTcpServer(broker, port)
            .WithTlsOptions(a=> a.UseTls())
            .WithAuthentication("OAUTH2-JWT", GetToken())
            .Build();

        // Connect to the MQTT broker
        await mqttClient.ConnectAsync(options, CancellationToken.None);

        //handle token expiration
        _refreshTokenTime = new Timer(async o =>
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

        // Subscribe to the telemetry and reported property topics
        //await mqttClient.SubscribeAsync(new MqttTopicFilterBuilder().WithTopic("device/+/telemetry").Build());
        //await mqttClient.SubscribeAsync(new MqttTopicFilterBuilder().WithTopic("device/+/twin/reported").Build());
        await mqttClient.SubscribeAsync(new MqttTopicFilterBuilder().WithTopic("telemetry/+/#").Build());

       
        // Set up handlers
        mqttClient.ApplicationMessageReceivedAsync += HandleReceivedApplicationMessage;

        // Send a command to the device
        var commandTopic = "telemetry/my-device/temperature";
        var commandPayload = """
                             {
                                 "methodName": "SetLEDState",
                                 "payload": {
                                     "state": "on"
                                 }
                             }
                             """u8.ToArray();
        var commandMessage = new MqttApplicationMessageBuilder()
            .WithTopic(commandTopic)
            .WithPayload(commandPayload)
            .WithQualityOfServiceLevel(MqttQualityOfServiceLevel.AtMostOnce)
            .Build();
        await mqttClient.PublishAsync(commandMessage, System.Threading.CancellationToken.None);

        // Update a desired property
        var desiredPropertyTopic = "device/espDevice/twin/desired";
        var desiredPropertyPayload = """
                                     {
                                         "desired": {
                                             "TemperatureThreshold": 25
                                         }
                                     }
                                     """u8.ToArray();
        var desiredPropertyMessage = new MqttApplicationMessageBuilder()
            .WithTopic(desiredPropertyTopic)
            .WithPayload(desiredPropertyPayload)
            .WithQualityOfServiceLevel(MqttQualityOfServiceLevel.AtMostOnce)
            .Build();
        await mqttClient.PublishAsync(desiredPropertyMessage, CancellationToken.None);

        // Keep the application running until manually stopped
        Console.WriteLine("Press any key to exit...");
        Console.ReadKey();

        // Disconnect the client
        await mqttClient.DisconnectAsync();
    }

    private static Task HandleReceivedApplicationMessage(MqttApplicationMessageReceivedEventArgs e)
    {
        Console.WriteLine($"Received message on topic: {e.ApplicationMessage.Topic}");
        Console.WriteLine($"Message Payload: {Encoding.UTF8.GetString(e.ApplicationMessage.Payload)}");
        return Task.CompletedTask;
    }
    
    static byte[] GetToken()
    {
        var clientSecretCredential = new ClientSecretCredential("e0a3cb79-6bd3-4062-8afc-431690b67672",
            "13de0305-97f4-4b18-8f39-921bd6145815", "6fO8Q~NbWWC2SuHSiFCBRWaBlllTsZrgr2.7~ayV");
    
        
        AccessToken jwt =
            clientSecretCredential.GetToken(new TokenRequestContext(["https://eventgrid.azure.net/.default"]));
        return Encoding.UTF8.GetBytes(jwt.Token);
    }
}