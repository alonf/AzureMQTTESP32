using System;
using System.Threading.Tasks;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace MQTTCloudController
{
    // ReSharper disable once ClassNeverInstantiated.Global
    public class DeviceMessagesHandler(ILogger<DeviceMessagesHandler> _logger)
    {
        [Function(nameof(DeviceMessagesHandler))]
        public async Task Run(
            [ServiceBusTrigger("%ServiceBusMqttMessageQueueName%", Connection = "ServiceBusConnection")]
            ServiceBusReceivedMessage message,
            ServiceBusMessageActions messageActions)
        {
            _logger.LogInformation("Message ID: {id}", message.MessageId);
            _logger.LogInformation("Message Body: {body}", message.Body);
            _logger.LogInformation("Message Content-Type: {contentType}", message.ContentType);

            var jsonBody = System.Text.Json.JsonDocument.Parse(message.Body);
            var dataBase64 = jsonBody.RootElement.GetProperty("data_base64").GetString();

            if (!string.IsNullOrEmpty(dataBase64))
            {
                var data = Convert.FromBase64String(dataBase64);
                var dataString = System.Text.Encoding.UTF8.GetString(data);
                _logger.LogInformation("Message Data: {data}", dataString);
            }
            else
            {
                _logger.LogInformation("Message Data: {data}", "No data");
            }

            // Complete the message
            await messageActions.CompleteMessageAsync(message);
        }
    }
}
