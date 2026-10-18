'use strict';

// FR-5.3 chat filters. Pure functions so they are easy to unit-test.

// Words are compared after normalisation (see normalise); suffixes catch simple plurals/verbs.
const DICTIONARY = ['badword', 'porn', 'scam', 'fuck', 'shit', 'bitch', 'asshole', 'idiotspam'];
const SUFFIXES = ['', 's', 'es', 'ing', 'er', 'ers', 'ed'];

const LEET = { '@': 'a', 0: 'o', 1: 'i', '!': 'i', 3: 'e', $: 's' };
const ZERO_WIDTH = /[​-‍⁠﻿]/g;

// Leetspeak normalisation: @->a 0->o 1/!->i 3->e $->s, separators _ . - * and zero-width removed.
function normalise(token) {
  return token
    .replace(ZERO_WIDTH, '')
    .toLowerCase()
    .replace(/[@01!3$]/g, (c) => LEET[c])
    .replace(/[_.\-*]/g, '');
}

const inDictionary = (n) => n.length > 0 && DICTIONARY.some((w) => SUFFIXES.some((s) => n === w + s));

// "!" stands for "i" (sh!t) but is also used as a plain separator (s!c@m), so both are tried.
const isProfane = (token) => inDictionary(normalise(token)) || inDictionary(normalise(token.replace(/!/g, '')));

// Leading/trailing sentence punctuation is kept outside the word ("word!" -> "word" + "!").
// Inner characters like the ! in s!c@m stay, so they are normalised as leetspeak.
const EDGE = /^([("'“‘]*)(.*?)([)"'”’.,;:?!]*)$/s;

// Returns { text, flagged } with every offending word replaced by ***.
function maskProfanity(text) {
  let flagged = false;
  const out = text.split(/(\s+)/).map((part) => {
    if (!part || /^\s+$/.test(part)) return part;
    if (isProfane(part)) {
      flagged = true;
      return '***';
    }
    const [, lead, core, trail] = EDGE.exec(part);
    if (core && isProfane(core)) {
      flagged = true;
      return `${lead}***${trail}`;
    }
    return part;
  });
  return { text: out.join(''), flagged };
}

// >= 4 identical characters in a row (case-insensitive, not spaces) or >= 3 of ! / ? in a row.
const isFlood = (text) => /(\S)\1{3,}/iu.test(text.replace(ZERO_WIDTH, '')) || /[!?]{3,}/.test(text);

module.exports = { normalise, isProfane, maskProfanity, isFlood, DICTIONARY };
