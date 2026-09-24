import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { authApi } from '../api/endpoints.js';
import { setCsrfToken } from '../api/client.js';
import { setFormattingConfig } from '../utils/format.js';

const AuthContext = createContext(null);

function normalizeSession(payload) {
  const data = payload?.data || {};
  const user = data.user || data.usuario || (data.authenticated === false ? null : data.account || null);
  return {
    user,
    forcePasswordChange: Boolean(
      data.forcePasswordChange ?? data.mustChangePassword ?? user?.forcePasswordChange ?? user?.mustChangePassword,
    ),
    csrfToken: data.csrfToken,
    locale: data.locale,
  };
}

export function AuthProvider({ children }) {
  const [status, setStatus] = useState('loading');
  const [user, setUser] = useState(null);
  const [forcePasswordChange, setForcePasswordChange] = useState(false);
  const [terminationReason, setTerminationReason] = useState(null);

  const applySession = useCallback((payload) => {
    const session = normalizeSession(payload);
    setCsrfToken(session.csrfToken);
    setFormattingConfig(session.locale);
    setUser(session.user);
    setForcePasswordChange(session.forcePasswordChange);
    setStatus(session.user ? 'authenticated' : 'anonymous');
    return session;
  }, []);

  const refreshSession = useCallback(async (signal) => {
    setStatus((current) => (current === 'authenticated' ? current : 'loading'));
    try {
      const response = await authApi.session(signal);
      applySession(response);
    } catch (error) {
      if (error?.name === 'AbortError') return;
      setCsrfToken(null);
      setUser(null);
      setForcePasswordChange(false);
      setStatus('anonymous');
    }
  }, [applySession]);

  useEffect(() => {
    const controller = new AbortController();
    refreshSession(controller.signal);
    return () => controller.abort();
  }, [refreshSession]);

  useEffect(() => {
    const handleUnauthorized = (event) => {
      if (status !== 'authenticated') return;
      setCsrfToken(null);
      setUser(null);
      setForcePasswordChange(false);
      setTerminationReason(event.detail?.message || 'Tu sesión terminó. Vuelve a iniciar sesión.');
      setStatus('anonymous');
    };
    window.addEventListener('securefinance:unauthorized', handleUnauthorized);
    return () => window.removeEventListener('securefinance:unauthorized', handleUnauthorized);
  }, [status]);

  const login = useCallback(async (credentials) => {
    const response = await authApi.login(credentials);
    const session = applySession(response);
    setTerminationReason(null);
    return session;
  }, [applySession]);

  const logout = useCallback(async () => {
    try {
      await authApi.logout();
    } catch (error) {
      if (error?.status !== 401) throw error;
    } finally {
      setCsrfToken(null);
      setUser(null);
      setForcePasswordChange(false);
      setTerminationReason(null);
      setStatus('anonymous');
    }
  }, []);

  const updateUser = useCallback((patch) => {
    setUser((current) => (current ? { ...current, ...patch } : current));
  }, []);

  const clearTerminationReason = useCallback(() => setTerminationReason(null), []);

  const value = useMemo(() => ({
    status,
    user,
    forcePasswordChange,
    terminationReason,
    login,
    logout,
    refreshSession,
    updateUser,
    clearTerminationReason,
  }), [status, user, forcePasswordChange, terminationReason, login, logout, refreshSession, updateUser, clearTerminationReason]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const value = useContext(AuthContext);
  if (!value) throw new Error('useAuth debe utilizarse dentro de AuthProvider.');
  return value;
}
