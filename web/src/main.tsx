import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./theme/index.css";
import { App } from "./app";

const root = document.getElementById("root");
if (!root) throw new Error("#root not found");

createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
