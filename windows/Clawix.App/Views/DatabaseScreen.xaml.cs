using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class DatabaseScreen : UserControl
{
    public DatabaseScreen() { InitializeComponent(); }
}

// Placeholder DataGrid until CommunityToolkit.WinUI.UI.Controls.DataGrid is wired in.
public sealed class DataGrid : ListView { }
