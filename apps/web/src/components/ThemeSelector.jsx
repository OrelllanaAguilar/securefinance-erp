import { Monitor, Moon, Sun } from 'lucide-react';
import { useTheme } from '../contexts/ThemeContext.jsx';

const OPTIONS = [
  { value: 'claro', label: 'Claro', Icon: Sun },
  { value: 'oscuro', label: 'Oscuro', Icon: Moon },
  { value: 'sistema', label: 'Sistema', Icon: Monitor },
];

export function ThemeSelector({ compact = false }) {
  const { preference, setPreference, saveState, retrySave } = useTheme();
  return (
    <div className={`theme-control ${compact ? 'theme-control--compact' : ''}`}>
      <label htmlFor={compact ? 'theme-compact' : 'theme'} className={compact ? 'sr-only' : undefined}>
        Apariencia
      </label>
      <div className="select-with-icon">
        {(() => {
          const selected = OPTIONS.find((item) => item.value === preference) || OPTIONS[2];
          return <selected.Icon aria-hidden="true" size={16} />;
        })()}
        <select
          id={compact ? 'theme-compact' : 'theme'}
          value={preference}
          onChange={(event) => setPreference(event.target.value)}
          aria-describedby={saveState.status === 'error' ? 'theme-save-error' : undefined}
        >
          {OPTIONS.map(({ value, label }) => <option key={value} value={value}>{label}</option>)}
        </select>
      </div>
      {saveState.status === 'error' && (
        <div className="field-note field-note--warning" id="theme-save-error" role="status">
          {saveState.message}{' '}
          <button type="button" className="link-button" onClick={retrySave}>Reintentar</button>
        </div>
      )}
    </div>
  );
}
