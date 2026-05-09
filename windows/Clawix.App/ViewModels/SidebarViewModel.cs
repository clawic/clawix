using System.Collections.ObjectModel;
using Clawix.Core.Models;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Clawix.App.ViewModels;

public sealed partial class SidebarViewModel : ObservableObject
{
    public ObservableCollection<WireChat> Chats { get; } = new();

    [ObservableProperty]
    private string _searchQuery = string.Empty;

    [ObservableProperty]
    private WireChat? _selectedChat;

    public SidebarViewModel()
    {
        var state = App.Services.State;
        state.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(state.Chats))
                ReplaceChats(state.Chats);
        };
    }

    private void ReplaceChats(IEnumerable<WireChat> chats)
    {
        Chats.Clear();
        foreach (var c in chats) Chats.Add(c);
    }

    [RelayCommand]
    private async Task SelectChatAsync(WireChat chat)
    {
        SelectedChat = chat;
        await App.Services.State.SelectChatAsync(chat);
    }

    [RelayCommand]
    private void NewChat()
    {
        // Open ProjectEditorSheet then send `newChat`. Wired in Phase 4.
    }
}
