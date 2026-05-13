using System.Collections.ObjectModel;
using Clawix.Core.Models;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Clawix.App.ViewModels;

public sealed partial class SidebarViewModel : ObservableObject
{
    public ObservableCollection<WireChat> Sessions { get; } = new();

    [ObservableProperty]
    private string _searchQuery = string.Empty;

    [ObservableProperty]
    private WireChat? _selectedChat;

    public SidebarViewModel()
    {
        var state = App.Services.State;
        state.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(state.Sessions))
                ReplaceChats(state.Sessions);
        };
    }

    private void ReplaceChats(IEnumerable<WireChat> chats)
    {
        Sessions.Clear();
        foreach (var c in chats) Sessions.Add(c);
    }

    [RelayCommand]
    private async Task SelectChatAsync(WireChat chat)
    {
        SelectedChat = chat;
        await App.Services.State.SelectChatAsync(chat);
    }

    [RelayCommand]
    private void NewSession()
    {
        // Open ProjectEditorSheet then send `newChat`. Wired in Phase 4.
    }
}
