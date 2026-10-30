import type { DigestResult } from '../digest/types.js';

export function Digest({ night, digest }: { night: string; digest: DigestResult }) {
  return (
    <>
      <h1>digest · {night}</h1>
      {digest.rows.length === 0 && <p class="mute">nothing ran</p>}
      <table>
        <thead>
          <tr>
            <th>job</th><th>owner</th><th>runs</th><th>retries</th>
            <th>last status</th><th>last error</th><th>first</th><th>last</th>
          </tr>
        </thead>
        <tbody>
          {digest.rows.map((row) => (
            <tr class={row.retries >= 3 || row.lastStatus === 'fail' ? 'warn' : undefined}>
              <td>{row.job || '—'}</td>
              <td>{row.owner || '—'}</td>
              <td>{row.runs}</td>
              <td>{row.retries}</td>
              <td>{row.lastStatus}</td>
              <td>{row.lastError || '—'}</td>
              <td>{row.firstTime || '—'}</td>
              <td>{row.lastTime || '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {digest.badLines > 0 && (
        <p class="mute">
          {digest.badLines} {digest.badLines === 1 ? 'line could' : 'lines could'} not be read
        </p>
      )}
    </>
  );
}
