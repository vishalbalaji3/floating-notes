import { EditorState, EditorSelection } from '@codemirror/state';
import { EditorView, Decoration, ViewPlugin, WidgetType, keymap } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { markdown } from '@codemirror/lang-markdown';
import { syntaxHighlighting, HighlightStyle, syntaxTree } from '@codemirror/language';
import { search, searchKeymap, highlightSelectionMatches } from '@codemirror/search';
import { GFM } from '@lezer/markdown';
import { tags } from '@lezer/highlight';

let editor;
let suppressChanges = false;

function bridge(action, data = {}) {
  window.webkit?.messageHandlers?.bridge?.postMessage({ action, ...data });
}

class CheckboxWidget extends WidgetType {
  constructor(checked, markerFrom) {
    super();
    this.checked = checked;
    this.markerFrom = markerFrom;
  }

  eq(other) {
    return this.checked === other.checked && this.markerFrom === other.markerFrom;
  }

  toDOM(view) {
    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.checked = this.checked;
    checkbox.className = 'cm-task-checkbox';
    checkbox.setAttribute('aria-label', this.checked ? 'Mark incomplete' : 'Mark complete');
    checkbox.addEventListener('mousedown', (event) => {
      event.preventDefault();
      view.dispatch({
        changes: {
          from: this.markerFrom,
          to: this.markerFrom + 3,
          insert: this.checked ? '[ ]' : '[x]',
        },
      });
      view.focus();
    });
    return checkbox;
  }

  ignoreEvent() { return false; }
}

function buildPreviewDecorations(view) {
  const decorations = [];
  const lineClasses = new Set();
  const selection = view.state.selection.main;
  const cursorLine = view.state.doc.lineAt(selection.head).number;

  const cursorInside = (from, to) => selection.from >= from && selection.to <= to;
  const cursorOnLine = (position) => view.state.doc.lineAt(position).number === cursorLine;
  const addLine = (position, className) => {
    const lineStart = view.state.doc.lineAt(position).from;
    const key = `${lineStart}:${className}`;
    if (lineClasses.has(key)) return;
    lineClasses.add(key);
    decorations.push(Decoration.line({ class: className }).range(lineStart));
  };

  addLine(view.state.doc.line(cursorLine).from, 'cm-active-markdown-line');

  for (const visible of view.visibleRanges) {
    syntaxTree(view.state).iterate({
      from: visible.from,
      to: visible.to,
      enter(node) {
        const parent = node.node.parent;
        const parentFrom = parent?.from ?? node.from;
        const parentTo = parent?.to ?? node.to;

        switch (node.name) {
          case 'ATXHeading1': addLine(node.from, 'cm-heading cm-heading-1'); break;
          case 'ATXHeading2': addLine(node.from, 'cm-heading cm-heading-2'); break;
          case 'ATXHeading3': addLine(node.from, 'cm-heading cm-heading-3'); break;
          case 'ATXHeading4': addLine(node.from, 'cm-heading cm-heading-4'); break;
          case 'ATXHeading5': addLine(node.from, 'cm-heading cm-heading-5'); break;
          case 'ATXHeading6': addLine(node.from, 'cm-heading cm-heading-6'); break;

          case 'StrongEmphasis':
            decorations.push(Decoration.mark({ class: 'cm-live-bold' }).range(node.from, node.to));
            break;
          case 'Emphasis':
            decorations.push(Decoration.mark({ class: 'cm-live-italic' }).range(node.from, node.to));
            break;
          case 'Strikethrough':
            decorations.push(Decoration.mark({ class: 'cm-live-strike' }).range(node.from, node.to));
            break;
          case 'InlineCode':
            decorations.push(Decoration.mark({ class: 'cm-live-inline-code' }).range(node.from, node.to));
            break;

          case 'HeaderMark':
            if (!cursorOnLine(node.from)) {
              decorations.push(Decoration.replace({}).range(node.from, node.to));
            } else {
              decorations.push(Decoration.mark({ class: 'cm-markdown-marker' }).range(node.from, node.to));
            }
            break;

          case 'EmphasisMark':
          case 'StrikethroughMark':
          case 'CodeMark':
            if (!cursorInside(parentFrom, parentTo)) {
              decorations.push(Decoration.replace({}).range(node.from, node.to));
            } else {
              decorations.push(Decoration.mark({ class: 'cm-markdown-marker' }).range(node.from, node.to));
            }
            break;

          case 'Link':
            decorations.push(Decoration.mark({ class: 'cm-live-link' }).range(node.from, node.to));
            break;
          case 'LinkMark':
          case 'URL':
            if (!cursorInside(parentFrom, parentTo)) {
              decorations.push(Decoration.replace({}).range(node.from, node.to));
            } else {
              decorations.push(Decoration.mark({ class: 'cm-markdown-marker' }).range(node.from, node.to));
            }
            break;

          case 'Blockquote': {
            const first = view.state.doc.lineAt(node.from).number;
            const last = view.state.doc.lineAt(node.to).number;
            for (let line = first; line <= last; line += 1) {
              addLine(view.state.doc.line(line).from, 'cm-live-quote');
            }
            break;
          }
          case 'QuoteMark':
            decorations.push(Decoration.mark({ class: 'cm-markdown-marker' }).range(node.from, node.to));
            break;

          case 'FencedCode': {
            const first = view.state.doc.lineAt(node.from).number;
            const last = view.state.doc.lineAt(node.to).number;
            for (let line = first; line <= last; line += 1) {
              addLine(view.state.doc.line(line).from, 'cm-live-code-block');
            }
            break;
          }
          case 'CodeInfo':
            decorations.push(Decoration.mark({ class: 'cm-code-language' }).range(node.from, node.to));
            break;
          case 'ListMark':
            if (/^ \[[ xX]\]/.test(view.state.sliceDoc(node.to, node.to + 4))) break;
            decorations.push(Decoration.mark({ class: 'cm-list-marker' }).range(node.from, node.to));
            break;
          case 'TaskMarker': {
            const possibleListStart = node.from - 2;
            const fullFrom = possibleListStart >= 0
              && view.state.sliceDoc(possibleListStart, node.from) === '- '
              ? possibleListStart
              : node.from;
            if (cursorOnLine(node.from)) break;
            const marker = view.state.sliceDoc(node.from, node.to);
            decorations.push(
              Decoration.replace({
                widget: new CheckboxWidget(/[xX]/.test(marker), node.from),
              }).range(fullFrom, node.to)
            );
            break;
          }
          case 'Table': {
            const first = view.state.doc.lineAt(node.from).number;
            const last = view.state.doc.lineAt(node.to).number;
            for (let line = first; line <= last; line += 1) {
              addLine(view.state.doc.line(line).from, 'cm-live-table');
            }
            break;
          }
          case 'TableHeader': addLine(node.from, 'cm-live-table-header'); break;
          case 'HorizontalRule': addLine(node.from, 'cm-live-rule'); break;
          default: break;
        }
      },
    });
  }

  // Markdown has no standard underline syntax. Floating Notes stores underline as HTML and
  // previews <u>text</u> in the same cursor-aware style as other inline formatting.
  const source = view.state.doc.toString();
  const underlinePattern = /<u>([^\n]*?)<\/u>/gi;
  let match;
  while ((match = underlinePattern.exec(source)) !== null) {
    const from = match.index;
    const to = from + match[0].length;
    const openingEnd = from + 3;
    const closingStart = to - 4;
    decorations.push(Decoration.mark({ class: 'cm-live-underline' }).range(openingEnd, closingStart));
    if (!cursorInside(from, to)) {
      decorations.push(Decoration.replace({}).range(from, openingEnd));
      decorations.push(Decoration.replace({}).range(closingStart, to));
    } else {
      decorations.push(Decoration.mark({ class: 'cm-markdown-marker' }).range(from, openingEnd));
      decorations.push(Decoration.mark({ class: 'cm-markdown-marker' }).range(closingStart, to));
    }
  }

  return Decoration.set(decorations, true);
}

const previewPlugin = ViewPlugin.fromClass(class {
  constructor(view) { this.decorations = buildPreviewDecorations(view); }
  update(update) {
    if (update.docChanged || update.selectionSet || update.viewportChanged) {
      this.decorations = buildPreviewDecorations(update.view);
    }
  }
}, { decorations: (value) => value.decorations });

function wrapSelection(view, opening, closing) {
  const { from, to } = view.state.selection.main;
  const selected = view.state.sliceDoc(from, to);
  const before = view.state.sliceDoc(Math.max(0, from - opening.length), from);
  const after = view.state.sliceDoc(to, Math.min(view.state.doc.length, to + closing.length));

  if (selected.startsWith(opening) && selected.endsWith(closing) && selected.length >= opening.length + closing.length) {
    const inner = selected.slice(opening.length, selected.length - closing.length);
    view.dispatch({
      changes: { from, to, insert: inner },
      selection: EditorSelection.range(from, from + inner.length),
    });
  } else if (before === opening && after === closing) {
    view.dispatch({
      changes: [
        { from: from - opening.length, to: from, insert: '' },
        { from: to, to: to + closing.length, insert: '' },
      ],
      selection: EditorSelection.range(from - opening.length, to - opening.length),
    });
  } else if (from === to) {
    view.dispatch({
      changes: { from, insert: opening + closing },
      selection: EditorSelection.cursor(from + opening.length),
    });
  } else {
    view.dispatch({
      changes: { from, to, insert: opening + selected + closing },
      selection: EditorSelection.range(from + opening.length, to + opening.length),
    });
  }
  view.focus();
}

function selectedLines(view) {
  const selection = view.state.selection.main;
  const firstLine = view.state.doc.lineAt(selection.from);
  const lastPosition = selection.to > selection.from ? selection.to - 1 : selection.to;
  const lastLine = view.state.doc.lineAt(lastPosition);
  const lines = [];
  for (let number = firstLine.number; number <= lastLine.number; number += 1) {
    lines.push(view.state.doc.line(number));
  }
  return lines;
}

function toggleLinePrefix(view, prefix, pattern) {
  const lines = selectedLines(view);
  const populated = lines.filter((line) => line.text.trim().length > 0);
  const remove = populated.length > 0 && populated.every((line) => pattern.test(line.text));
  const changes = [];

  lines.forEach((line, index) => {
    if (!line.text.trim()) return;
    const match = line.text.match(pattern);
    if (remove && match) {
      changes.push({ from: line.from, to: line.from + match[0].length, insert: '' });
    } else if (!remove && !match) {
      const insertion = typeof prefix === 'function' ? prefix(index) : prefix;
      changes.push({ from: line.from, insert: insertion });
    }
  });

  if (changes.length) view.dispatch({ changes });
  view.focus();
}

function applyFormatting(action, level = 1) {
  if (!editor) return;
  switch (action) {
    case 'bold': wrapSelection(editor, '**', '**'); break;
    case 'italic': wrapSelection(editor, '*', '*'); break;
    case 'underline': wrapSelection(editor, '<u>', '</u>'); break;
    case 'strikethrough': wrapSelection(editor, '~~', '~~'); break;
    case 'inlineCode': wrapSelection(editor, '`', '`'); break;
    case 'heading': {
      const wanted = `${'#'.repeat(Math.min(6, Math.max(1, level)))} `;
      const changes = [];
      selectedLines(editor).forEach((line) => {
        if (!line.text.trim()) return;
        const existing = line.text.match(/^#{1,6}\s+/)?.[0];
        if (existing === wanted) {
          changes.push({ from: line.from, to: line.from + existing.length, insert: '' });
        } else if (existing) {
          changes.push({ from: line.from, to: line.from + existing.length, insert: wanted });
        } else {
          changes.push({ from: line.from, insert: wanted });
        }
      });
      if (changes.length) editor.dispatch({ changes });
      editor.focus();
      break;
    }
    case 'quote': toggleLinePrefix(editor, '> ', /^>\s/); break;
    case 'bulletList': toggleLinePrefix(editor, '- ', /^[-+*]\s/); break;
    case 'numberedList': toggleLinePrefix(editor, (index) => `${index + 1}. `, /^\d+\.\s/); break;
    case 'checklist': toggleLinePrefix(editor, '- [ ] ', /^-\s\[[ xX]\]\s/); break;
    case 'link': {
      const range = editor.state.selection.main;
      const selected = editor.state.sliceDoc(range.from, range.to) || 'text';
      const replacement = `[${selected}](url)`;
      const urlFrom = range.from + selected.length + 3;
      editor.dispatch({
        changes: { from: range.from, to: range.to, insert: replacement },
        selection: EditorSelection.range(urlFrom, urlFrom + 3),
      });
      editor.focus();
      break;
    }
    case 'codeBlock': {
      const range = editor.state.selection.main;
      const selected = editor.state.sliceDoc(range.from, range.to);
      const replacement = selected ? `\`\`\`\n${selected}\n\`\`\`` : '\`\`\`\n\n\`\`\`';
      editor.dispatch({
        changes: { from: range.from, to: range.to, insert: replacement },
        selection: selected
          ? EditorSelection.range(range.from + 4, range.from + 4 + selected.length)
          : EditorSelection.cursor(range.from + 4),
      });
      editor.focus();
      break;
    }
    default: break;
  }
}

const formattingKeymap = [
  { key: 'Mod-k', run: () => { bridge('showActions'); return true; } },
  { key: 'Mod-,', run: () => { bridge('showSettings'); return true; } },
  { key: 'Mod-b', run: (view) => { wrapSelection(view, '**', '**'); return true; } },
  { key: 'Mod-i', run: (view) => { wrapSelection(view, '*', '*'); return true; } },
  { key: 'Mod-u', run: (view) => { wrapSelection(view, '<u>', '</u>'); return true; } },
  { key: 'Mod-Shift-x', run: (view) => { wrapSelection(view, '~~', '~~'); return true; } },
  { key: 'Mod-l', run: () => { applyFormatting('link'); return true; } },
  { key: 'Mod-e', run: (view) => { wrapSelection(view, '`', '`'); return true; } },
];

const highlightStyle = HighlightStyle.define([
  { tag: tags.heading, fontWeight: '700' },
  { tag: tags.strong, fontWeight: '700' },
  { tag: tags.emphasis, fontStyle: 'italic' },
  { tag: tags.monospace, fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace' },
  { tag: tags.link, color: 'var(--editor-link)' },
]);

const theme = EditorView.theme({
  '&': {
    height: '100%',
    color: 'var(--editor-text)',
    backgroundColor: 'transparent',
    fontSize: '15px',
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
  },
  '&.cm-focused': { outline: 'none' },
  '.cm-scroller': { overflow: 'auto', fontFamily: 'inherit' },
  '.cm-content': { minHeight: '100%', padding: '14px 16px 56px', caretColor: '#3b82f6' },
  '.cm-content:empty::before': {
    content: 'attr(data-placeholder)',
    color: 'var(--editor-tertiary)',
    opacity: '0.65',
    pointerEvents: 'none',
  },
  '.cm-line': { padding: '1px 0', lineHeight: '1.55' },
  '.cm-cursor': { borderLeftColor: '#3b82f6', borderLeftWidth: '2px' },
  '.cm-selectionBackground, &.cm-focused .cm-selectionBackground': { backgroundColor: 'rgba(55, 132, 255, 0.24)' },
  '.cm-gutters': { display: 'none' },
  '.cm-heading': { fontWeight: '700', lineHeight: '1.3', paddingTop: '5px', paddingBottom: '2px' },
  '.cm-heading-1': { fontSize: '1.75em' },
  '.cm-heading-2': { fontSize: '1.45em' },
  '.cm-heading-3': { fontSize: '1.25em' },
  '.cm-heading-4': { fontSize: '1.12em' },
  '.cm-heading-5': { fontSize: '1.05em' },
  '.cm-heading-6': { fontSize: '1em' },
  '.cm-live-bold': { fontWeight: '700' },
  '.cm-live-italic': { fontStyle: 'italic' },
  '.cm-live-underline': { textDecoration: 'underline' },
  '.cm-live-strike': { textDecoration: 'line-through', opacity: '0.65' },
  '.cm-markdown-marker': { opacity: '0.3' },
  '.cm-live-inline-code': {
    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
    fontSize: '0.9em',
    backgroundColor: 'rgba(127, 127, 127, 0.13)',
    borderRadius: '4px',
  },
  '.cm-live-link': { color: 'var(--editor-link)', textDecoration: 'underline', textUnderlineOffset: '2px' },
  '.cm-live-quote': { borderLeft: '3px solid rgba(80, 120, 180, 0.55)', paddingLeft: '10px', color: 'var(--editor-secondary)' },
  '.cm-live-code-block': {
    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
    fontSize: '0.9em',
    backgroundColor: 'rgba(127, 127, 127, 0.10)',
    paddingLeft: '10px',
    paddingRight: '10px',
  },
  '.cm-code-language': { opacity: '0.45', fontSize: '0.85em' },
  '.cm-list-marker': { color: 'var(--editor-secondary)', fontWeight: '600' },
  '.cm-task-checkbox': { margin: '0 6px 0 1px', verticalAlign: 'middle', cursor: 'pointer' },
  '.cm-live-table': {
    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
    fontSize: '0.88em',
    backgroundColor: 'rgba(127, 127, 127, 0.08)',
    paddingLeft: '8px',
  },
  '.cm-live-table-header': { fontWeight: '700' },
  '.cm-live-rule': { borderBottom: '1px solid rgba(127, 127, 127, 0.4)', color: 'transparent' },
  '.cm-panels': { backgroundColor: 'var(--editor-panel)', color: 'var(--editor-text)' },
  '.cm-searchMatch': { backgroundColor: 'rgba(255, 190, 40, 0.4)' },
  '.cm-searchMatch-selected': { backgroundColor: 'rgba(255, 145, 30, 0.55)' },
});

function createEditor() {
  const state = EditorState.create({
    extensions: [
      history(),
      keymap.of([...formattingKeymap, ...searchKeymap, ...defaultKeymap, ...historyKeymap]),
      markdown({ extensions: GFM }),
      syntaxHighlighting(highlightStyle),
      previewPlugin,
      search({ top: true }),
      highlightSelectionMatches(),
      theme,
      EditorView.lineWrapping,
      EditorView.contentAttributes.of({ 'data-placeholder': 'Start writing…', spellcheck: 'true' }),
      EditorView.updateListener.of((update) => {
        if (update.docChanged && !suppressChanges) {
          bridge('contentChanged', { content: update.state.doc.toString() });
        }
        if (update.selectionSet || update.docChanged) {
          bridge('selectionChanged', { position: update.state.selection.main.head });
        }
      }),
    ],
  });

  editor = new EditorView({ state, parent: document.getElementById('editor') });
  bridge('ready');
}

window.setContent = (content, cursor = 0) => {
  if (!editor) return;
  const safeCursor = Math.max(0, Math.min(cursor, content.length));
  suppressChanges = true;
  editor.dispatch({
    changes: { from: 0, to: editor.state.doc.length, insert: content },
    selection: EditorSelection.cursor(safeCursor),
    scrollIntoView: true,
  });
  suppressChanges = false;
};

window.applyFormatting = applyFormatting;
window.focusEditor = () => editor?.focus();
window.getContent = () => editor?.state.doc.toString() ?? '';

window.addEventListener('error', (event) => {
  bridge('error', { message: event.message || 'Unknown editor error' });
});

document.addEventListener('DOMContentLoaded', createEditor);
