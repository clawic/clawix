using System.Collections.ObjectModel;
using Clawix.Core.Models;
using CommunityToolkit.Mvvm.ComponentModel;

namespace Clawix.App.ViewModels;

public sealed partial class ChatViewModel : ObservableObject
{
    public ObservableCollection<WireMessage> Messages { get; } = new();

    [ObservableProperty]
    private string _title = "Welcome to Clawix";

    public ChatViewModel()
    {
        var state = App.Services.State;
        state.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(state.CurrentMessages))
            {
                Messages.Clear();
                foreach (var m in state.CurrentMessages) Messages.Add(m);
            }
            else if (args.PropertyName == nameof(state.CurrentChat))
            {
                Title = state.CurrentChat?.Title ?? "Welcome to Clawix";
            }
        };
    }
}
