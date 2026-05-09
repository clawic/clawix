using System.Collections.ObjectModel;
using Clawix.Core.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class SidebarView : UserControl
{
    public ObservableCollection<WireChat> Chats { get; } = new();

    public SidebarView()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        var state = App.Services.State;
        state.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(state.Chats))
                DispatcherQueue.TryEnqueue(() =>
                {
                    Chats.Clear();
                    foreach (var c in state.Chats) Chats.Add(c);
                });
            if (args.PropertyName == nameof(state.BridgeStateLabel))
                DispatcherQueue.TryEnqueue(() => BridgeStatusText.Text = state.BridgeStateLabel);
        };
        BridgeStatusText.Text = state.BridgeStateLabel;
    }

    private async void ChatList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ChatList.SelectedItem is WireChat chat)
            await App.Services.State.SelectChatAsync(chat);
    }

    private void NewChat_Click(object sender, RoutedEventArgs e)
    {
        // Phase 4: open ProjectEditorSheet to pick the cwd, then send `newChat` frame.
    }

    private void Settings_Click(object sender, RoutedEventArgs e)
    {
        // Open Settings as a separate window so chat stays visible.
        var win = new SettingsWindow();
        win.Activate();
    }
}
