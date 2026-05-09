using Clawix.App.Views.Settings;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Animation;

namespace Clawix.App.Views;

public sealed partial class SettingsView : UserControl
{
    public SettingsView()
    {
        InitializeComponent();
        Loaded += (_, _) =>
        {
            // Default to General. Use a NavigationView SelectionChanged
            // listener for routing.
            ContentFrame.Navigate(typeof(GeneralPage));
        };

        var nav = (NavigationView)Content;
        nav.SelectionChanged += Nav_SelectionChanged;
        nav.SelectedItem = nav.MenuItems[0];
    }

    private void Nav_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItemContainer?.Tag is not string tag) return;
        Type page = tag switch
        {
            "general"     => typeof(GeneralPage),
            "account"     => typeof(AccountPage),
            "models"      => typeof(ModelsPage),
            "localModels" => typeof(LocalModelsPage),
            "dictation"   => typeof(DictationSettingsPage),
            "quickAsk"    => typeof(QuickAskSettingsPage),
            "secrets"     => typeof(SecretsPage),
            "mcp"         => typeof(MCPPage),
            "database"    => typeof(DatabasePage),
            "updates"     => typeof(UpdatesPage),
            "pairing"     => typeof(PairingPage),
            "privacy"     => typeof(PrivacyPage),
            "about"       => typeof(AboutPage),
            _             => typeof(GeneralPage),
        };
        ContentFrame.Navigate(page, null, new EntranceNavigationTransitionInfo());
    }
}
