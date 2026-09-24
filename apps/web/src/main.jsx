import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { createBrowserRouter, RouterProvider } from 'react-router';
import App from './App.jsx';
import { AuthProvider } from './contexts/AuthContext.jsx';
import { ThemeProvider } from './contexts/ThemeContext.jsx';
import './styles/index.css';

function Root() {
  return <AuthProvider><ThemeProvider><App /></ThemeProvider></AuthProvider>;
}

const router = createBrowserRouter([{ path: '*', element: <Root /> }]);

createRoot(document.getElementById('root')).render(
  <StrictMode><RouterProvider router={router} /></StrictMode>,
);
