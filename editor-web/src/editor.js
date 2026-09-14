import { defaultKeymap, indentWithTab } from '@codemirror/commands';
import {
  HighlightStyle,
  bracketMatching,
  syntaxHighlighting,
} from '@codemirror/language';
import { languages } from '@codemirror/language-data';
import {
  EditorView as CodeMirrorView,
  highlightActiveLine,
  highlightActiveLineGutter,
  keymap as codeMirrorKeymap,
  lineNumbers,
} from '@codemirror/view';
import { tags } from '@lezer/highlight';
import { codeBlockComponent, codeBlockConfig } from '@milkdown/kit/component/code-block';
import {
  Editor,
  defaultValueCtx,
  editorViewCtx,
  editorViewOptionsCtx,
  remarkStringifyOptionsCtx,
  rootCtx,
  serializerCtx,
} from '@milkdown/kit/core';
import {
  commonmark,
  linkSchema,
  toggleEmphasisCommand,
  toggleInlineCodeCommand,
  toggleStrongCommand,
  wrapInBlockquoteCommand,
  wrapInBulletListCommand,
  wrapInHeadingCommand,
  wrapInOrderedListCommand,
  createCodeBlockCommand,
} from '@milkdown/kit/preset/commonmark';
import { gfm, toggleStrikethroughCommand } from '@milkdown/kit/preset/gfm';
import { clipboard } from '@milkdown/kit/plugin/clipboard';
import { cursor } from '@milkdown/kit/plugin/cursor';
import { history } from '@milkdown/kit/plugin/history';
import { listener, listenerCtx } from '@milkdown/kit/plugin/listener';
import { toggleMark } from '@milkdown/kit/prose/commands';
import { TextSelection } from '@milkdown/kit/prose/state';
import { $markSchema, $remark, callCommand, replaceAll } from '@milkdown/kit/utils';

let editor;

const codeHighlightStyle = HighlightStyle.define([
  { tag: [tags.keyword, tags.modifier, tags.operatorKeyword], color: 'var(--code-keyword)' },
  { tag: [tags.name, tags.variableName, tags.propertyName], color: 'var(--code-name)' },
  { tag: [tags.string, tags.special(tags.string)], color: 'var(--code-string)' },
  { tag: [tags.number, tags.bool, tags.null], color: 'var(--code-number)' },
  { tag: [tags.typeName, tags.className, tags.namespace], color: 'var(--code-type)' },
  { tag: [tags.function(tags.variableName), tags.labelName], color: 'var(--code-function)' },
  { tag: [tags.comment, tags.meta], color: 'var(--code-comment)', fontStyle: 'italic' },
  { tag: [tags.punctuation, tags.bracket], color: 'var(--code-punctuation)' },
  { tag: tags.invalid, color: 'var(--code-invalid)' },
]);

function bridge(action, data = {}) {
  window.webkit?.messageHandlers?.bridge?.postMessage({ action, ...data });
}

// Keep Floating Notes' existing <u>...</u> convention as a real Milkdown mark.
const underlineRemark = $remark('floatingNotesUnderline', () => () => (tree) => {
  const visit = (node) => {
    if (!Array.isArray(node.children)) return;
    node.children.forEach(visit);
    const children = [];
    for (let index = 0; index < node.children.length; index += 1) {
      const child = node.children[index];
      if (child.type !== 'html' || !/^<u>$/i.test(child.value?.trim?.() ?? '')) {
        children.push(child);
        continue;
      }
      const marked = [];
      let closing = index + 1;
      while (closing < node.children.length) {
        const candidate = node.children[closing];
        if (candidate.type === 'html' && /^<\/u>$/i.test(candidate.value?.trim?.() ?? '')) break;
        marked.push(candidate);
        closing += 1;
      }
      if (closing < node.children.length) {
        children.push({ type: 'floatingNotesUnderline', children: marked });
        index = closing;
      } else {
        children.push(child);
      }
    }
    node.children = children;
  };
  visit(tree);
});

const underlineSchema = $markSchema('floating_notes_underline', () => ({
  parseDOM: [{ tag: 'u' }],
  toDOM: () => ['u', 0],
  parseMarkdown: {
    match: (node) => node.type === 'floatingNotesUnderline',
    runner: (state, node, markType) => {
      state.openMark(markType);
      state.next(node.children);
      state.closeMark(markType);
    },
  },
  toMarkdown: {
    match: (mark) => mark.type.name === 'floating_notes_underline',
    runner: (state, mark) => {
      state.withMark(mark, 'floatingNotesUnderline');
    },
  },
}));

function runCommand(command, payload) {
  if (!editor) return false;
  const handled = editor.action(callCommand(command.key, payload));
  editor.action((ctx) => ctx.get(editorViewCtx).focus());
  return handled;
}

function toggleUnderline() {
  if (!editor) return;
  editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    toggleMark(underlineSchema.type(ctx))(view.state, view.dispatch, view);
    view.focus();
  });
}

function insertLink() {
  if (!editor) return;
  const dialog = document.getElementById('link-dialog');
  const label = document.getElementById('link-label');
  const url = document.getElementById('link-url');
  const selection = editor.action((ctx) => {
    const { state } = ctx.get(editorViewCtx);
    return {
      from: state.selection.from,
      to: state.selection.to,
      text: state.doc.textBetween(state.selection.from, state.selection.to),
    };
  });

  label.value = selection.text;
  url.value = '';
  dialog.querySelector('form').onsubmit = (event) => {
    event.preventDefault();
    if (!url.reportValidity()) return;
    editor.action((ctx) => {
      const view = ctx.get(editorViewCtx);
      const mark = linkSchema.type(ctx).create({ href: url.value, title: null });
      const text = label.value || url.value;
      const { tr } = view.state;
      if (selection.from === selection.to) {
        tr.insertText(text, selection.from).addMark(selection.from, selection.from + text.length, mark);
      } else {
        if (text !== selection.text) tr.insertText(text, selection.from, selection.to);
        tr.addMark(selection.from, selection.from + text.length, mark);
      }
      tr.setSelection(TextSelection.create(tr.doc, selection.from + text.length));
      view.dispatch(tr.scrollIntoView());
      view.focus();
    });
    dialog.close();
  };
  dialog.showModal();
  url.focus();
}

function makeChecklist() {
  if (!editor) return;
  runCommand(wrapInBulletListCommand);
  editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    const { from, to, $from } = view.state.selection;
    const tr = view.state.tr;
    for (let depth = $from.depth; depth > 0; depth -= 1) {
      const node = $from.node(depth);
      if (node.type.name === 'list_item') {
        tr.setNodeMarkup($from.before(depth), undefined, { ...node.attrs, checked: false });
        break;
      }
    }
    view.state.doc.nodesBetween(from, to, (node, position) => {
      if (node.type.name === 'list_item') {
        tr.setNodeMarkup(position, undefined, { ...node.attrs, checked: false });
      }
    });
    if (tr.docChanged) view.dispatch(tr);
    view.focus();
  });
}

function applyFormatting(action, level = 1) {
  switch (action) {
    case 'bold': runCommand(toggleStrongCommand); break;
    case 'italic': runCommand(toggleEmphasisCommand); break;
    case 'underline': toggleUnderline(); break;
    case 'strikethrough': runCommand(toggleStrikethroughCommand); break;
    case 'inlineCode': runCommand(toggleInlineCodeCommand); break;
    case 'heading': runCommand(wrapInHeadingCommand, Math.min(6, Math.max(1, level))); break;
    case 'quote': runCommand(wrapInBlockquoteCommand); break;
    case 'bulletList': runCommand(wrapInBulletListCommand); break;
    case 'numberedList': runCommand(wrapInOrderedListCommand); break;
    case 'checklist': makeChecklist(); break;
    case 'link': insertLink(); break;
    case 'codeBlock': runCommand(createCodeBlockCommand, ''); break;
    default: break;
  }
}

function handleShortcut(event) {
  if (!event.metaKey || event.ctrlKey) return;
  const key = event.key.toLowerCase();
  let action;
  if (key === 'k' && !event.shiftKey && !event.altKey) {
    event.preventDefault();
    bridge('showActions');
    return;
  }
  if (key === ',' && !event.shiftKey && !event.altKey) {
    event.preventDefault();
    bridge('showSettings');
    return;
  }
  if (key === 'b' && event.shiftKey) action = 'quote';
  else if (key === 'b' && !event.altKey) action = 'bold';
  else if (key === 'i' && !event.shiftKey && !event.altKey) action = 'italic';
  else if (key === 'u' && !event.shiftKey && !event.altKey) action = 'underline';
  else if (key === 'x' && event.shiftKey && !event.altKey) action = 'strikethrough';
  else if (key === 'l' && !event.shiftKey && !event.altKey) action = 'link';
  else if (key === 'e' && !event.shiftKey && !event.altKey) action = 'inlineCode';
  else if (key === 'c' && event.altKey && !event.shiftKey) action = 'codeBlock';
  if (!action) return;
  event.preventDefault();
  event.stopPropagation();
  applyFormatting(action);
}

function handleEditorClick(event) {
  if (event.button !== 0) return;

  const anchor = event.target.closest?.('a[href]');
  if (anchor && /^https?:\/\//i.test(anchor.href)) {
    event.preventDefault();
    bridge('openURL', { url: anchor.href });
    return;
  }

  const item = event.target.closest?.('li[data-item-type="task"]');
  if (!item || !editor) return;

  const itemBounds = item.getBoundingClientRect();
  const checkboxStyle = getComputedStyle(item, '::before');
  const checkboxBounds = {
    left: itemBounds.left + Number.parseFloat(checkboxStyle.left),
    top: itemBounds.top + Number.parseFloat(checkboxStyle.top),
    width: Number.parseFloat(checkboxStyle.width),
    height: Number.parseFloat(checkboxStyle.height),
  };
  if (Object.values(checkboxBounds).some((value) => !Number.isFinite(value))) return;
  if (
    event.clientX < checkboxBounds.left
    || event.clientX > checkboxBounds.left + checkboxBounds.width
    || event.clientY < checkboxBounds.top
    || event.clientY > checkboxBounds.top + checkboxBounds.height
  ) return;

  event.preventDefault();
  editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    const position = view.posAtDOM(item, 0) - 1;
    const node = view.state.doc.nodeAt(position);
    if (node?.type.name !== 'list_item') return;
    view.dispatch(view.state.tr.setNodeMarkup(position, undefined, { ...node.attrs, checked: !node.attrs.checked }));
    view.focus();
  });
}

async function createEditor() {
  editor = Editor.make()
    .config((ctx) => {
      ctx.set(rootCtx, document.getElementById('editor'));
      ctx.set(defaultValueCtx, '');
      ctx.update(remarkStringifyOptionsCtx, (options) => ({
        ...options,
        handlers: {
          ...options.handlers,
          floatingNotesUnderline: (node, _parent, state, info) =>
            `<u>${state.containerPhrasing(node, info)}</u>`,
        },
      }));
      ctx.update(editorViewOptionsCtx, (options) => ({
        ...options,
        attributes: {
          ...options.attributes,
          spellcheck: 'true',
          'aria-label': 'Markdown note editor',
        },
      }));
      ctx.update(codeBlockConfig.key, (options) => ({
        ...options,
        languages,
        extensions: [
          lineNumbers(),
          highlightActiveLineGutter(),
          highlightActiveLine(),
          bracketMatching(),
          syntaxHighlighting(codeHighlightStyle, { fallback: true }),
          codeMirrorKeymap.of([indentWithTab, ...defaultKeymap]),
          CodeMirrorView.lineWrapping,
        ],
        expandIcon: '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="m3.25 5.75 4.75 4.5 4.75-4.5"/></svg>',
        searchIcon: '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="7" cy="7" r="4.25"/><path d="m10.25 10.25 3 3"/></svg>',
        clearSearchIcon: '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="m4 4 8 8m0-8-8 8"/></svg>',
        copyIcon: '<svg viewBox="0 0 16 16" aria-hidden="true"><rect x="5.25" y="2.25" width="8" height="9" rx="1.25"/><path d="M10.75 13.75H3.5a1.25 1.25 0 0 1-1.25-1.25V5.25"/></svg>',
      }));
      ctx.get(listenerCtx)
        .markdownUpdated((_ctx, markdown) => bridge('contentChanged', { content: markdown }))
        .selectionUpdated((_ctx, selection) => bridge('selectionChanged', { position: selection.head }));
    })
    .use(underlineRemark)
    .use(underlineSchema)
    .use(commonmark)
    .use(gfm)
    .use(codeBlockComponent)
    .use(history)
    .use(clipboard)
    .use(cursor)
    .use(listener);

  await editor.create();
  document.addEventListener('keydown', handleShortcut, true);
  document.getElementById('editor').addEventListener('mousedown', handleEditorClick);
  bridge('ready');
}

window.setContent = (content, cursorPosition = 0) => {
  if (!editor) return;
  document.getElementById('link-dialog').close();
  editor.action(replaceAll(content, true));
  editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    const position = Math.max(0, Math.min(cursorPosition, view.state.doc.content.size));
    const selection = TextSelection.near(view.state.doc.resolve(position));
    view.dispatch(view.state.tr.setSelection(selection).setMeta('addToHistory', false).scrollIntoView());
  });
};

window.applyFormatting = applyFormatting;
window.focusEditor = () => editor?.action((ctx) => ctx.get(editorViewCtx).focus());
window.getContent = () => editor?.action((ctx) => ctx.get(serializerCtx)(ctx.get(editorViewCtx).state.doc)) ?? '';

window.addEventListener('error', (event) => bridge('error', { message: event.message || 'Unknown editor error' }));
window.addEventListener('unhandledrejection', (event) => bridge('error', { message: String(event.reason || 'Editor failed to load') }));
document.addEventListener('DOMContentLoaded', () => {
  createEditor().catch((error) => bridge('error', { message: String(error) }));
});
