import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scriptDirectory, '..');
const docsDirectory = path.join(root, 'docs');
const sources = [
  'README.md',
  'architecture.md',
  'physical-erd.md',
  'technical-decisions.md',
  'api-contracts.md',
  'stored-procedures.md',
  'traceability.md',
  'user-manual.md',
  'backup-restore.md',
  'test-matrix.md',
  'quality-plan.md',
  'verification-results.md',
  'evidence-guide.md',
  'demo-script.md',
];

function escapeHtml(value) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function inline(value) {
  return escapeHtml(value)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\[([^\]]+)]\(([^)]+)\)/g, '<a href="$2">$1</a>');
}

function tableCells(line) {
  return line
    .trim()
    .replace(/^\|/, '')
    .replace(/\|$/, '')
    .split('|')
    .map((cell) => cell.trim());
}

function isTableDivider(line) {
  return /^\s*\|?\s*:?-{3,}/.test(line) && line.includes('|');
}

function renderMarkdown(markdown) {
  const lines = markdown.replaceAll('\r\n', '\n').split('\n');
  const output = [];
  let index = 0;
  while (index < lines.length) {
    const line = lines[index];
    if (line.startsWith('```')) {
      const language = line.slice(3).trim();
      const code = [];
      index += 1;
      while (index < lines.length && !lines[index].startsWith('```')) {
        code.push(lines[index]);
        index += 1;
      }
      output.push(`<pre data-language="${escapeHtml(language)}"><code>${escapeHtml(code.join('\n'))}</code></pre>`);
      index += 1;
      continue;
    }
    const heading = /^(#{1,6})\s+(.+)$/.exec(line);
    if (heading) {
      const level = Math.min(heading[1].length + 1, 6);
      output.push(`<h${level}>${inline(heading[2])}</h${level}>`);
      index += 1;
      continue;
    }
    if (line.includes('|') && index + 1 < lines.length && isTableDivider(lines[index + 1])) {
      const headers = tableCells(line);
      const rows = [];
      index += 2;
      while (index < lines.length && lines[index].includes('|') && lines[index].trim()) {
        rows.push(tableCells(lines[index]));
        index += 1;
      }
      output.push('<div class="table-scroll"><table><thead><tr>');
      output.push(headers.map((cell) => `<th>${inline(cell)}</th>`).join(''));
      output.push('</tr></thead><tbody>');
      for (const row of rows) output.push(`<tr>${row.map((cell) => `<td>${inline(cell)}</td>`).join('')}</tr>`);
      output.push('</tbody></table></div>');
      continue;
    }
    if (/^\s*[-*]\s+/.test(line)) {
      const items = [];
      while (index < lines.length && /^\s*[-*]\s+/.test(lines[index])) {
        items.push(lines[index].replace(/^\s*[-*]\s+/, ''));
        index += 1;
      }
      output.push(`<ul>${items.map((item) => `<li>${inline(item)}</li>`).join('')}</ul>`);
      continue;
    }
    if (/^\s*\d+\.\s+/.test(line)) {
      const items = [];
      while (index < lines.length && /^\s*\d+\.\s+/.test(lines[index])) {
        items.push(lines[index].replace(/^\s*\d+\.\s+/, ''));
        index += 1;
      }
      output.push(`<ol>${items.map((item) => `<li>${inline(item)}</li>`).join('')}</ol>`);
      continue;
    }
    if (/^>\s?/.test(line)) {
      output.push(`<blockquote>${inline(line.replace(/^>\s?/, ''))}</blockquote>`);
      index += 1;
      continue;
    }
    if (/^---+$/.test(line.trim())) {
      output.push('<hr>');
      index += 1;
      continue;
    }
    if (!line.trim()) {
      index += 1;
      continue;
    }
    const paragraph = [line.trim()];
    index += 1;
    while (
      index < lines.length &&
      lines[index].trim() &&
      !/^(#{1,6})\s+/.test(lines[index]) &&
      !/^\s*[-*]\s+/.test(lines[index]) &&
      !/^\s*\d+\.\s+/.test(lines[index]) &&
      !lines[index].startsWith('```') &&
      !(lines[index].includes('|') && index + 1 < lines.length && isTableDivider(lines[index + 1]))
    ) {
      paragraph.push(lines[index].trim());
      index += 1;
    }
    output.push(`<p>${inline(paragraph.join(' '))}</p>`);
  }
  return output.join('\n');
}

const sections = [];
for (const source of sources) {
  const sourcePath = path.join(docsDirectory, source);
  try {
    const markdown = await fs.readFile(sourcePath, 'utf8');
    sections.push(`<section class="document-section" data-source="${escapeHtml(source)}">${renderMarkdown(markdown)}</section>`);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

const generatedAt = new Intl.DateTimeFormat('es-GT', {
  dateStyle: 'long',
  timeStyle: 'short',
  timeZone: 'America/Guatemala',
}).format(new Date());

const html = `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SecureFinance ERP — Documento técnico</title>
<style>
  :root { color: #232323; background: #f8f7f4; font-family: "Segoe UI", system-ui, sans-serif; }
  * { box-sizing: border-box; }
  body { margin: 0; line-height: 1.48; font-size: 10.5pt; }
  main { max-width: 1024px; margin: 0 auto; padding: 40px 52px 80px; background: white; }
  .cover { min-height: 88vh; display: grid; align-content: center; border-top: 8px solid #b99a59; page-break-after: always; }
  .cover-mark { color: #7a5b20; font-size: 14px; font-weight: 700; letter-spacing: .14em; text-transform: uppercase; }
  .cover h1 { margin: 20px 0 8px; font-size: 38px; line-height: 1.08; }
  .cover h2 { margin: 0 0 36px; color: #5f5c56; font-size: 22px; font-weight: 500; }
  .cover-meta { border-left: 3px solid #b99a59; padding-left: 18px; color: #5f5c56; }
  .document-section { page-break-before: always; }
  h2 { margin-top: 0; color: #201a0f; font-size: 25px; border-bottom: 2px solid #d8d3c8; padding-bottom: 8px; }
  h3 { margin-top: 28px; color: #3b3428; font-size: 18px; }
  h4, h5, h6 { margin-top: 22px; color: #4c4437; }
  p, li { orphans: 3; widows: 3; }
  a { color: #7a5b20; text-decoration: none; }
  code { font-family: Consolas, monospace; background: #f4ecdc; padding: 1px 4px; border-radius: 3px; }
  pre { padding: 14px; border: 1px solid #d8d3c8; background: #f8f7f4; white-space: pre-wrap; overflow-wrap: anywhere; page-break-inside: avoid; }
  pre code { padding: 0; background: transparent; }
  table { width: 100%; border-collapse: collapse; margin: 14px 0 20px; font-size: 8.5pt; }
  th, td { border: 1px solid #d8d3c8; padding: 6px 7px; vertical-align: top; text-align: left; }
  th { background: #f4ecdc; color: #382b16; }
  tr { page-break-inside: avoid; }
  blockquote { margin: 16px 0; padding: 10px 16px; border-left: 3px solid #b99a59; background: #f8f7f4; }
  hr { border: 0; border-top: 1px solid #d8d3c8; margin: 28px 0; }
  @page { size: A4; margin: 16mm 14mm 18mm; }
  @media print { body, main { background: white; } main { max-width: none; padding: 0; } a { color: #232323; } }
</style>
</head>
<body><main>
  <section class="cover">
    <div class="cover-mark">SecureFinance ERP · versión académica 2.0</div>
    <h1>Documento técnico</h1>
    <h2>Arquitectura, seguridad, operación, pruebas y trazabilidad</h2>
    <div class="cover-meta">
      <p><strong>Stack:</strong> React, Express y Microsoft SQL Server</p>
      <p><strong>Generado:</strong> ${escapeHtml(generatedAt)}</p>
      <p>Las pruebas conservan su estado documentado; este PDF no convierte revisión estática en evidencia de ejecución.</p>
    </div>
  </section>
  ${sections.join('\n')}
</main></body></html>`;

await fs.writeFile(path.join(docsDirectory, 'technical-report.html'), html, 'utf8');
console.info('Documento HTML generado: docs/technical-report.html');
