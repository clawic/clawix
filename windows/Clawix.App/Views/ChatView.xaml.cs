using System.Collections.ObjectModel;
using Clawix.Core.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class ChatView : UserControl
{
    public ObservableCollection<WireMessage> Messages { get; } = new();
    public string Title { get; private set; } = "Welcome to Clawix";

    public ChatView()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        var state = App.Services.State;
        state.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(state.CurrentMessages))
                DispatcherQueue.TryEnqueue(() =>
                {
                    Messages.Clear();
                    foreach (var m in state.CurrentMessages) Messages.Add(m);
                });
            if (args.PropertyName == nameof(state.CurrentChat))
                DispatcherQueue.TryEnqueue(() =>
                {
                    Title = state.CurrentChat?.Title ?? "Welcome to Clawix";
                    TitleText.Text = Title;
                });
        };
    }
}
