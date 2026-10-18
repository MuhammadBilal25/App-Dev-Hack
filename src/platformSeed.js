'use strict';

// Platform data that is not part of the Section 5.5 contract: display metadata for sports, store
// categories, platform settings. Re-created by every reset alongside seed.js. Nothing in here is
// read by a domain engine to decide behaviour; engines only read the sport config itself.

// Display metadata per sport (shown in the sports directory). `icon` is a generic icon key the
// app maps to an icon; unknown keys fall back to a generic trophy.
const SPORT_META = {
  football: { description: 'Two halves of 45 minutes. Goals decide the match; draws count in leagues.', icon: 'soccer', active: true },
  basketball: { description: 'Four 12-minute quarters. Free throws, two- and three-pointers; overtime breaks ties.', icon: 'basketball', active: true },
  cricket: { description: 'Limited-overs innings. Runs, wickets, extras and net run rate.', icon: 'cricket', active: true },
  esports: { description: 'Best-of-N series decided by rounds or maps won.', icon: 'esports', active: true },
};

const CATEGORIES = [
  { category_id: 'apparel', name: 'Jerseys & shirts' },
  { category_id: 'sportswear', name: 'Shorts & sportswear' },
  { category_id: 'training', name: 'Training kits' },
  { category_id: 'caps', name: 'Caps' },
  { category_id: 'bags', name: 'Bags' },
  { category_id: 'accessories', name: 'Accessories' },
  { category_id: 'digital', name: 'Digital items' },
];

const SETTINGS = {
  // When true, a League Organizer may create clubs inside the leagues they run.
  organizer_can_create_clubs: false,
  // Variants at or below this many units are listed as low stock.
  low_stock_threshold: 3,
  currency: 'PKR',
  // Hours a team must rest between two fixtures (fixture conflict detection).
  min_rest_hours: 12,
};

// Clock hours (UTC) during which venues accept fixtures unless a venue sets its own.
const DEFAULT_VENUE_HOURS = { open: '06:00', close: '23:00' };

module.exports = { SPORT_META, CATEGORIES, SETTINGS, DEFAULT_VENUE_HOURS };
