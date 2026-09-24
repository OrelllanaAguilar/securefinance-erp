import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { meApi } from '../api/endpoints.js';
import { useAuth } from './AuthContext.jsx';

const STORAGE_KEY = 'securefinance.anonymousTheme';
const VALUES = new Set(['claro', 'oscuro', 'sistema']);
const ThemeContext = createContext(null);

function validTheme(value) {
  return VALUES.has(value) ? value : 'sistema';
}

function readAnonymousTheme() {
  try {
    return validTheme(localStorage.getItem(STORAGE_KEY));
  } catch {
    return 'sistema';
  }
}

function userTheme(user) {
  return validTheme(user?.theme ?? user?.preferences?.theme ?? user?.preference?.theme ?? user?.themePreference ?? user?.tema);
}

function applyTheme(preference) {
  const dark = preference === 'oscuro' || (
    preference === 'sistema' && window.matchMedia?.('(prefers-color-scheme: dark)').matches
  );
  const resolved = dark ? 'dark' : 'light';
  document.documentElement.dataset.theme = resolved;
  document.documentElement.dataset.themePreference = preference;
  const colorScheme = document.querySelector('meta[name="color-scheme"]');
  if (colorScheme) colorScheme.content = resolved;
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.content = dark ? '#141414' : '#f8f7f4';
  return resolved;
}

export function ThemeProvider({ children }) {
  const { status, user, forcePasswordChange, updateUser } = useAuth();
  const authenticated = status === 'authenticated';
  const accountPreferencesAllowed = authenticated && !forcePasswordChange;
  const [anonymousTheme, setAnonymousTheme] = useState(readAnonymousTheme);
  const [accountTheme, setAccountTheme] = useState(() => userTheme(user));
  const [resolvedTheme, setResolvedTheme] = useState(() => document.documentElement.dataset.theme || 'light');
  const [saveState, setSaveState] = useState({ status: 'idle', message: '' });
  const desiredRef = useRef(null);
  const savingRef = useRef(false);
  const accountThemeRef = useRef(accountTheme);

  const preference = authenticated ? accountTheme : anonymousTheme;

  useEffect(() => {
    if (authenticated) {
      const next = userTheme(user);
      accountThemeRef.current = next;
      setAccountTheme(next);
    } else {
      setSaveState({ status: 'idle', message: '' });
      desiredRef.current = null;
      accountThemeRef.current = anonymousTheme;
    }
  }, [authenticated, user, anonymousTheme]);

  useEffect(() => {
    setResolvedTheme(applyTheme(preference));
    const media = window.matchMedia?.('(prefers-color-scheme: dark)');
    if (!media || preference !== 'sistema') return undefined;
    const onChange = () => setResolvedTheme(applyTheme('sistema'));
    media.addEventListener('change', onChange);
    return () => media.removeEventListener('change', onChange);
  }, [preference]);

  const persistAccountTheme = useCallback(async () => {
    if (savingRef.current || !accountPreferencesAllowed) return;
    savingRef.current = true;
    while (desiredRef.current) {
      const target = desiredRef.current;
      desiredRef.current = null;
      setSaveState({ status: 'saving', message: 'Guardando apariencia…' });
      try {
        await meApi.preferences({ theme: target });
        if (!desiredRef.current) {
          updateUser({ theme: target, preferences: { ...(user?.preferences || {}), theme: target } });
          setSaveState({ status: 'saved', message: 'Apariencia guardada.' });
        }
      } catch {
        if (!desiredRef.current) {
          desiredRef.current = target;
          setSaveState({
            status: 'error',
            message: 'Aplicado en esta sesión; no se pudo guardar.',
          });
          break;
        }
      }
    }
    savingRef.current = false;
  }, [accountPreferencesAllowed, updateUser, user?.preferences]);

  const setPreference = useCallback((value) => {
    const next = validTheme(value);
    if (!authenticated) {
      setAnonymousTheme(next);
      try { localStorage.setItem(STORAGE_KEY, next); } catch { /* La memoria sigue siendo válida. */ }
      return;
    }
    accountThemeRef.current = next;
    setAccountTheme(next);
    desiredRef.current = next;
    void persistAccountTheme();
  }, [authenticated, persistAccountTheme]);

  const retrySave = useCallback(() => {
    if (!desiredRef.current) desiredRef.current = accountThemeRef.current;
    void persistAccountTheme();
  }, [persistAccountTheme]);

  useEffect(() => {
    const onStorage = (event) => {
      if (!authenticated && event.key === STORAGE_KEY) setAnonymousTheme(validTheme(event.newValue));
    };
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, [authenticated]);

  useEffect(() => {
    if (!accountPreferencesAllowed) return undefined;
    const syncOnFocus = async () => {
      if (savingRef.current || desiredRef.current) return;
      try {
        const response = await meApi.getPreferences();
        const next = validTheme(response.data?.theme);
        accountThemeRef.current = next;
        setAccountTheme(next);
      } catch {
        // Una lectura fallida nunca sobrescribe la preferencia de la cuenta.
      }
    };
    window.addEventListener('focus', syncOnFocus);
    return () => window.removeEventListener('focus', syncOnFocus);
  }, [accountPreferencesAllowed]);

  const value = useMemo(() => ({
    preference,
    resolvedTheme,
    setPreference,
    saveState,
    retrySave,
  }), [preference, resolvedTheme, setPreference, saveState, retrySave]);

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme() {
  const value = useContext(ThemeContext);
  if (!value) throw new Error('useTheme debe utilizarse dentro de ThemeProvider.');
  return value;
}
