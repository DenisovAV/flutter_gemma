/// The corpus this codelab searches.
///
/// Twelve recipes, small enough to read in one screen and to re-embed in a few
/// seconds on a phone. Everything here is plain Dart — no asset bundle, no
/// network — because the point of the codelab is what happens *after* you have
/// the text, and a corpus you can see beats one you have to go fetch.
///
/// The three fields beside [text] are not decoration. Step 4 turns them into a
/// `FilterSchema`, and between them they cover every filter the API has:
///
/// * [cuisine] is a **string** — `FieldMatchAny` ("italian or greek")
/// * [minutes] is a **number** — `FieldRange` ("under half an hour")
/// * [vegetarian] is a **bool** — `FieldEquals`
///
/// Their names matter too, and not for taste: a sqlite-vec filter field must
/// match `^[A-Za-z][A-Za-z0-9_]*$`, because the name becomes a real `vec0`
/// column and that grammar has no quoted-identifier form. `prep-minutes` would
/// be unrepresentable there. qdrant accepts far more, so staying inside
/// sqlite's set is what keeps Step 3's store swap a one-line change.
class Recipe {
  const Recipe({
    required this.id,
    required this.title,
    required this.text,
    required this.cuisine,
    required this.minutes,
    required this.vegetarian,
  });

  /// Stable id. This is what the vector store keys on, and what a retrieval
  /// result hands back — so it has to survive a re-index unchanged.
  final String id;

  final String title;

  /// What actually gets embedded. Note that the title is repeated inside it:
  /// the vector is built from this string alone, so anything you want the
  /// search to match on has to be in here, not only in a field beside it.
  final String text;

  final String cuisine;
  final int minutes;
  final bool vegetarian;
}

const kRecipes = <Recipe>[
  Recipe(
    id: 'cacio-e-pepe',
    title: 'Cacio e Pepe',
    text:
        'Cacio e Pepe. Tonnarelli tossed with pecorino romano and coarsely '
        'cracked black pepper, emulsified with starchy pasta water into a '
        'glossy sauce. Three ingredients, no cream, no butter.',
    cuisine: 'italian',
    minutes: 20,
    vegetarian: true,
  ),
  Recipe(
    id: 'ribollita',
    title: 'Ribollita',
    text:
        'Ribollita. A thick Tuscan soup of cannellini beans, cavolo nero and '
        'stale bread, simmered slowly until the bread collapses into the '
        'broth. Better on the second day, which is what the name means.',
    cuisine: 'italian',
    minutes: 90,
    vegetarian: true,
  ),
  Recipe(
    id: 'spaghetti-vongole',
    title: 'Spaghetti alle Vongole',
    text:
        'Spaghetti alle Vongole. Clams opened in white wine with garlic and '
        'chilli, the liquor reduced and tossed through spaghetti with parsley. '
        'The clams season the dish; add salt only at the very end.',
    cuisine: 'italian',
    minutes: 30,
    vegetarian: false,
  ),
  Recipe(
    id: 'horiatiki',
    title: 'Horiatiki Salad',
    text:
        'Horiatiki. Tomatoes, cucumber, green pepper, red onion and a slab of '
        'feta, dressed with olive oil and dried oregano. No lettuce — the '
        'village salad has never had lettuce in it.',
    cuisine: 'greek',
    minutes: 10,
    vegetarian: true,
  ),
  Recipe(
    id: 'gigantes-plaki',
    title: 'Gigantes Plaki',
    text:
        'Gigantes Plaki. Giant white beans baked in a tomato sauce with dill '
        'and plenty of olive oil, until the top browns and the beans go '
        'creamy. Eaten warm or at room temperature.',
    cuisine: 'greek',
    minutes: 75,
    vegetarian: true,
  ),
  Recipe(
    id: 'souvlaki',
    title: 'Pork Souvlaki',
    text:
        'Pork Souvlaki. Cubes of pork shoulder marinated in lemon, oregano and '
        'garlic, threaded onto skewers and grilled hard over charcoal until '
        'the edges char. Served with flatbread and raw onion.',
    cuisine: 'greek',
    minutes: 40,
    vegetarian: false,
  ),
  Recipe(
    id: 'dal-tadka',
    title: 'Dal Tadka',
    text:
        'Dal Tadka. Yellow lentils simmered to a puree, finished with a tadka '
        'of ghee, cumin, dried chillies and asafoetida poured over at the '
        'table so it hisses. The tempering is the dish, not a garnish.',
    cuisine: 'indian',
    minutes: 45,
    vegetarian: true,
  ),
  Recipe(
    id: 'jeera-aloo',
    title: 'Jeera Aloo',
    text:
        'Jeera Aloo. Boiled potatoes tossed in hot oil with cumin seeds, '
        'turmeric, green chilli and a squeeze of lime. A side dish that takes '
        'fifteen minutes and disappears faster than the main.',
    cuisine: 'indian',
    minutes: 15,
    vegetarian: true,
  ),
  Recipe(
    id: 'butter-chicken',
    title: 'Butter Chicken',
    text:
        'Butter Chicken. Yoghurt-marinated chicken cooked over high heat, then '
        'folded into a tomato and cream sauce with fenugreek leaf. Sweeter and '
        'milder than almost anything else on a restaurant menu.',
    cuisine: 'indian',
    minutes: 60,
    vegetarian: false,
  ),
  Recipe(
    id: 'miso-soup',
    title: 'Miso Soup',
    text:
        'Miso Soup. Dashi whisked with miso paste off the heat — boiling it '
        'kills the aroma — with silken tofu and wakame. Ready in the time it '
        'takes the dashi to come to temperature.',
    cuisine: 'japanese',
    minutes: 12,
    vegetarian: true,
  ),
  Recipe(
    id: 'oyakodon',
    title: 'Oyakodon',
    text:
        'Oyakodon. Chicken and onion simmered in dashi, soy and mirin, then '
        'bound with barely-set egg and slid over hot rice. The egg should '
        'still be running when it leaves the pan.',
    cuisine: 'japanese',
    minutes: 25,
    vegetarian: false,
  ),
  Recipe(
    id: 'agedashi-tofu',
    title: 'Agedashi Tofu',
    text:
        'Agedashi Tofu. Silken tofu dusted in potato starch, fried until the '
        'shell crackles, then sat in warm dashi with grated daikon and '
        'ginger. The contrast lasts about a minute, so serve it immediately.',
    cuisine: 'japanese',
    minutes: 30,
    vegetarian: true,
  ),
];
