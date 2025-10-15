/*-*- js-indent-level: 2 -*-*/
// Copyright 2025 by zrajm. Licenses: CC BY-SA (text), GPLv2 (code).

// Process all text nodes in the DOM.
function modifyTextNodes(func, node = document.body) {
  switch (node.nodeType) {
    case Node.TEXT_NODE: func(node); return
    case Node.ELEMENT_NODE: switch (node.tagName) {
      // These tags shouldn't be processed.
      case 'PRE': case 'SCRIPT': case 'STYLE': case 'SVG': case 'TT': return
    }
  }
  for (const child of node.childNodes) { modifyTextNodes(func, child) }
}

// Parse HTML, return array of DOM nodes.
function parseHtml(html) {
  let wrapper = document.createElement('div')
  wrapper.innerHTML = html
  return wrapper.childNodes
}

// Listener for toggling table columns.
function toggleColumn(evt) {
  const { currentTarget: form, target: { value: colName, checked } } = evt
  const $table   = $(form).closest('figure.table-gui').find('table')
  const colNames = $table.find('th').map(th => th.innerText)
  const colNum   = colNames.indexOf(colName) + 1
  if (!colNum) { return }
  $table.find(`tr > :nth-child(${colNum})`)
    .forEach(cell => cell.toggleAttribute('hidden', checked))
}

/*****************************************************************************/

// Complete country list here:
// https://gist.github.com/selimata/75b5301b132bd541fe31e49cc38f61dc
const flags = {
  '🇦🇺': 'Australia',
  '🇧🇾': 'Belarus',
  '🇧🇪': 'Belgium',
  '🇧🇷': 'Brazil',
  '🇨🇴': 'Colombia',
  '🇩🇰': 'Denmark',
  '🇫🇷': 'France',
  '🇩🇪': 'Germany',
  '🇬🇧': 'Great Britain',
  '🇮🇹': 'Italy',
  '🇳🇱': 'Netherlands',
  '🇷🇺': 'Russia',
  '🇸🇪': 'Sweden',
  '🇺🇸': 'United States',
}
const harveyBalls = {
  '○': ['#e22', 'No Latin symbols, non-linear', 'Not at all'],
  '◔': ['#f92', 'No Latin symbols, but linear', 'A little bit'],
  '◑': ['#fd0', 'Latin alphabet + odd symbols', 'Half'],
  '◕': ['#8c3', 'A few odd symbols', 'Mostly'],
  '●': ['#0b5', 'Written with Latin symbols', 'Completely'],
}

const flagRegex = RegExp(
  Object.keys({...flags, ...harveyBalls}).join('|'), 'gu')

document.addEventListener("scent:done", () => {

  // Add hover text to Unicode flags and Harvey balls.
  modifyTextNodes(node => {
    let modified = false
    const html = (node.data ?? '').replace(flagRegex, x => {
      modified = true
      return flags[x]
        ? `<span title="${flags[x]}">${x}</span>`
        : `<span style="color:${harveyBalls[x][0]}" ` +
          `title="${harveyBalls[x][1]}">${x}</span>`
    })
    if (modified) { node.replaceWith(...parseHtml(html)) }
  })

  // Add column selector for table.
  $('figure.table-gui').prepend($([
    `<form><b>Columns:</b>`,
    ...$('.sign-language-table th').map(th => {
      const x = th.innerText
      return `<label><input type=checkbox value="${x}"> ${x}</label>`
    })
  ].join('\n')).on('change', toggleColumn))

})

//[eof]
