using Clawix.Core;
using Clawix.Core.Models;
using CommunityToolkit.Mvvm.ComponentModel;
using Microsoft.Extensions.Logging;

namespace Clawix.App.Services;

/// <summary>
/// Single source of truth for chat list / current chat / messages
/// shown in the GUI. Mirrors the macOS <c>AppState</c>. ViewModels
/// observe <see cref="INotifyPropertyChanged"/> changes; the daemon
/// client pushes updates through <see cref="ApplyFrame"/>.
/// </summary>
public sealed partial class AppState : ObservableObject
{
    private readonly BackgroundBridgeService _bridge;
    private readonly ILogger<AppState> _logger;
    private DaemonClient? _client;

    [ObservableProperty]
    private List<WireChat> _chats = [];

    [ObservableProperty]
    private WireChat? _currentChat;

    [ObservableProperty]
    private List<WireMessage> _currentMessages = [];

    [ObservableProperty]
    private string _bridgeStateLabel = "disconnected";

    [ObservableProperty]
    private bool _connected;

    public AppState(BackgroundBridgeService bridge, ILogger<AppState> logger)
    {
        _bridge = bridge;
        _logger = logger;
    }

    public async Task EnsureConnectedAsync(string bearer, CancellationToken ct)
    {
        var probe = _bridge.Probe();
        if (!probe.Alive || probe.Port is null) { BridgeStateLabel = "daemon not running"; return; }
        if (_client is not null) return;

        _client = new DaemonClient(probe.Port.Value, bearer, App.Services.LoggerFactory.CreateLogger<DaemonClient>());
        _client.ConnectionStateChanged += alive => Connected = alive;
        _client.FrameReceived += ApplyFrame;
        await _client.ConnectAsync(ct);
        await _client.SendAsync(new BridgeFrame(new BridgeBody.ListSessions()), ct);
    }

    public void ApplyFrame(BridgeFrame frame)
    {
        switch (frame.Body)
        {
            case BridgeBody.AuthOk:
                BridgeStateLabel = "connected";
                break;
            case BridgeBody.AuthFailed af:
                BridgeStateLabel = $"auth failed: {af.Reason}";
                break;
            case BridgeBody.BridgeState bs:
                BridgeStateLabel = bs.State + (bs.Message is null ? "" : $" ({bs.Message})");
                break;
            case BridgeBody.SessionsSnapshot cs:
                Sessions = cs.Sessions.ToList();
                break;
            case BridgeBody.ChatUpdated cu:
                Sessions = Sessions.Select(c => c.Id == cu.Chat.Id ? cu.Chat : c).ToList();
                break;
            case BridgeBody.MessagesSnapshot ms when CurrentChat?.Id == ms.SessionId:
                CurrentMessages = ms.Messages.ToList();
                break;
            case BridgeBody.MessageAppended ma when CurrentChat?.Id == ma.SessionId:
                CurrentMessages = CurrentMessages.Append(ma.Message).ToList();
                break;
            case BridgeBody.MessageStreaming mst when CurrentChat?.Id == mst.SessionId:
                CurrentMessages = CurrentMessages.Select(m => m.Id == mst.MessageId
                    ? m with { Content = mst.Content, ReasoningText = mst.ReasoningText, StreamingFinished = mst.Finished }
                    : m).ToList();
                break;
        }
    }

    public Task SelectChatAsync(WireChat chat)
    {
        CurrentChat = chat;
        CurrentMessages = [];
        return _client?.SendAsync(new BridgeFrame(new BridgeBody.OpenSession(chat.Id, BridgeConstants.InitialPageLimit)), CancellationToken.None)
            ?? Task.CompletedTask;
    }

    public Task SendPromptAsync(string text)
    {
        if (CurrentChat is null || _client is null) return Task.CompletedTask;
        return _client.SendAsync(new BridgeFrame(new BridgeBody.SendPrompt(CurrentChat.Id, text, [])), CancellationToken.None);
    }
}
