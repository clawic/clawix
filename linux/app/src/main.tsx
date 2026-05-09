/* @refresh reload */
import { render } from "solid-js/web";
import { Router, Route } from "@solidjs/router";
import App from "./App";
import ChatView from "./views/ChatView";
import SettingsView from "./views/SettingsView";
import BridgePairing from "./views/BridgePairing";
import VaultManagement from "./views/VaultManagement";
import UpdaterDialog from "./views/UpdaterDialog";
import QuickAskHUD from "./views/QuickAskHUD";
import About from "./views/About";
import "./styles/index.css";

const root = document.getElementById("root");
if (!root) throw new Error("missing #root in index.html");

render(
  () => (
    <Router root={App}>
      <Route path="/" component={ChatView} />
      <Route path="/chats/:id" component={ChatView} />
      <Route path="/settings" component={SettingsView} />
      <Route path="/pairing" component={BridgePairing} />
      <Route path="/vault" component={VaultManagement} />
      <Route path="/updater" component={UpdaterDialog} />
      <Route path="/quickask" component={QuickAskHUD} />
      <Route path="/about" component={About} />
    </Router>
  ),
  root
);
