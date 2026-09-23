import React from 'react';
import './index.css';
import { ChakraProvider } from "@chakra-ui/react";
import { theme } from "./theme";
import App from './components/App';
import { VisibilityProvider } from './providers/VisibilityProvider';
import { debugData } from "./utils/debugData";
import { createRoot } from 'react-dom/client';

debugData([
  {
    action: "setVisible",
    data: true,
  },
]);


const root = createRoot(document.getElementById('root')!);

root.render(
  <React.StrictMode>
    <VisibilityProvider>
      <ChakraProvider theme={theme}>
        <App />
      </ChakraProvider>
    </VisibilityProvider>
  </React.StrictMode>
);
