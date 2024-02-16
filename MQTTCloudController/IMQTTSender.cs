using Microsoft.AspNetCore.Mvc;

namespace MQTTCloudController;

public interface IMQTTSender
{
    Task<IActionResult> ConnectAsync();
    Task<IActionResult> PublishAsync(string topic, string payload);
    Task DisconnectAsync();
}