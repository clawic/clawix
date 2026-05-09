using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class RecoveryPhraseSheet : ContentDialog
{
    public RecoveryPhraseSheet() { InitializeComponent(); }
    public void SetPhrase(string phrase) => PhraseText.Text = phrase;
}
