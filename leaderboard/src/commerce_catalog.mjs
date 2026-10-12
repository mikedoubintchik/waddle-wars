// Server prices and grant lists are authoritative. Keep the game data in sync;
// tests compare both catalogs. Clients never supply price IDs or grant lists.
export const PRODUCTS = Object.freeze([
  Object.freeze({ id: 'cozy_expedition', name: 'Cozy Expedition',
    description: 'Cozy Beanie, Red Scarf and Snowflake Trail. Dress for the long waddle.',
    cosmetics: ['hat_beanie', 'scarf_red', 'trail_snowflake'], currency: 'usd', price_minor: 299,
    apple_product_id: 'com.blubberandbyte.waddlewars.cozy_expedition',
    google_product_id: 'com.blubberandbyte.waddlewars.cozy_expedition' }),
  Object.freeze({ id: 'research_crew', name: 'Research Crew',
    description: 'Research Headset, Bow Tie and Ski Goggles. Expedition-ready style.',
    cosmetics: ['hat_headset', 'scarf_bowtie', 'goggles_ski'], currency: 'usd', price_minor: 399,
    apple_product_id: 'com.blubberandbyte.waddlewars.research_crew',
    google_product_id: 'com.blubberandbyte.waddlewars.research_crew' }),
  Object.freeze({ id: 'aurora_celebration', name: 'Aurora Celebration',
    description: "Emperor's Crown, Rainbow Scarf and Aurora Trail. Celebrate in southern-light colors.",
    cosmetics: ['hat_crown', 'scarf_rainbow', 'trail_aurora'], currency: 'usd', price_minor: 499,
    apple_product_id: 'com.blubberandbyte.waddlewars.aurora_celebration',
    google_product_id: 'com.blubberandbyte.waddlewars.aurora_celebration' }),
]);
export const productById = (id) => PRODUCTS.find((product) => product.id === id);
export const DISCLOSURE = 'Cosmetics only. One-time purchases; no subscriptions, random rewards or gameplay bonuses. Every included cosmetic can also be earned with fish. Previously earned items receive no fish refund.';
