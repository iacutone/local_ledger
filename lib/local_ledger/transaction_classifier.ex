defmodule LocalLedger.TransactionClassifier do
  @moduledoc """
  Selects an expense account for a normalized transaction.

  Obvious merchant mappings stay local and deterministic. Unknown merchants are
  sent to the small Ollama classifier. Low-confidence answers are returned to
  the caller for user confirmation.
  """

  alias LocalLedger.Transaction

  @accounts [
    "Expenses:Online Services:Ebay",
    "Expenses:Online Services:Hulu",
    "Expenses:Online Services:Amazon",
    "Expenses:Online Services:Apple",
    "Expenses:Online Services:Google",
    "Expenses:Online Services:TLD",
    "Expenses:Entertainment",
    "Expenses:Food:Groceries",
    "Expenses:Food:Alcohol",
    "Expenses:Food:Coffee",
    "Expenses:Food:Delivery",
    "Expenses:Food:Restaurants",
    "Expenses:Clothing",
    "Expenses:Personal Care",
    "Expenses:Shopping",
    "Expenses:Books",
    "Expenses:Medical",
    "Expenses:Health:Fitness",
    "Expenses:Pets",
    "Expenses:Home",
    "Expenses:Auto",
    "Expenses:Transportation:Gas",
    "Expenses:Transportation:Rideshare",
    "Expenses:Transportation:Transit",
    "Expenses:Transportation",
    "Expenses:Utilities",
    "Expenses:Insurance:Car",
    "Expenses:Insurance",
    "Expenses:Postage",
    "Expenses:Travel",
    "Expenses:Miscellaneous",
    "Assets:Cash"
  ]

  @spec allowed_accounts() :: [String.t()]
  def allowed_accounts, do: @accounts

  @spec classify(Transaction.t(), keyword()) ::
          {:ok, %{account: String.t(), confidence: float(), source: atom()}}
          | {:error, String.t()}
  def classify(%Transaction{} = transaction, opts \\ []) do
    case known_account(transaction.description, transaction.category) do
      nil ->
        case LocalLedger.MerchantMemory.lookup(transaction.description) do
          nil -> LocalLedger.OllamaClient.classify(transaction, opts)
          account -> {:ok, %{account: account, confidence: 1.0, source: :memory}}
        end

      account ->
        {:ok, %{account: account, confidence: 1.0, source: :rule}}
    end
  end

  @spec prompt(Transaction.t()) :: String.t()
  def prompt(%Transaction{} = transaction) do
    """
    Classify this credit-card transaction into exactly one allowed account.
    Use the merchant description first and the bank category only as a hint.
    Return JSON only, with this exact shape:
    {"account":"Expenses:Shopping","confidence":0.0}

    Allowed accounts:
    #{Enum.join(@accounts, ", ")}

    Transaction:
    Description: #{transaction.description}
    Bank category: #{blank_as_unknown(transaction.category)}
    Type: #{blank_as_unknown(transaction.type)}
    Amount: #{transaction.amount}
    """
  end

  @doc false
  def known_account(description, category \\ nil)

  def known_account(description, category) when is_binary(description) do
    merchant = String.upcase(description)
    bank_category = String.upcase(to_string(category))

    cond do
      contains?(merchant, ["PAYPAL *EBAY SAVMYSERVER"]) -> "Expenses:Books"
      contains?(merchant, ["EBAY"]) -> "Expenses:Online Services:Ebay"
      contains?(merchant, ["HLU*", "HULU"]) -> "Expenses:Online Services:Hulu"
      contains?(merchant, ["PRIME VIDEO", "AMZN", "AMAZON", "KINDLE"]) -> "Expenses:Online Services:Amazon"
      contains?(merchant, ["APPLE.COM", "APL*", "ICLOUD", "ITUNES", "APPLE MUSIC"]) -> "Expenses:Online Services:Apple"
      contains?(merchant, ["GOOGLE *GOOGLE", "GOOGLE STORAGE", "YOUTUBE TV"]) -> "Expenses:Online Services:Google"
      contains?(merchant, ["NAME-CHEAP", "NAMECHEAP", "CLOUDFLARE", "GODADDY", "GO DADDY", "PORKBUN", "GANDI", "HOVER", "DYNADOT", "NAME.COM", "GOOGLE DOMAINS", "SQUARESPACE DOMAINS", "IONOS", "1AND1", "NETWORK SOLUTIONS", "REGISTER.COM"]) -> "Expenses:Online Services:TLD"
      contains?(merchant, ["NETFLIX", "DISNEY+", "DISNEY PLUS", "HBO", " MAX"]) -> "Expenses:Entertainment"
      contains?(merchant, ["SPOTIFY", "PANDORA", "YOUTUBE PREMIUM", "STEAMGAMES", "PLAYSTATION", "XBOX", "NINTENDO", "TWITCH", "AMC THEATRE", "REGAL", "CINEMARK", "IMAX", "MOVIE"]) -> "Expenses:Entertainment"
      contains?(merchant, ["COSTCO", "BJ'S", "BJS WHOLESALE", "SAM'S CLUB", "SAMS CLUB", "KROGER", "SAFEWAY", "WHOLE FOODS", "TRADER JOE", "PUBLIX", "ALDI", "WEIS", "WEGMANS", "H-E-B", "ALBERTSONS", "GROCERY", "SUPERMARKET", "FOOD LION", "STOP & SHOP", "STOP AND SHOP", "GIANT FOOD", "MEIJER", "SPROUTS", "FRESH MARKET", "MARKET BASKET", "HARRIS TEETER", "PRICE CHOPPER", "WINCO", "STATER BROS", "FOOD 4 LESS", "SMART & FINAL", "RALEY'S"]) -> "Expenses:Food:Groceries"
      contains?(merchant, ["TOTAL WINE", "LIQUOR", "BEER STORE", "WINE SHOP", "DRIZLY", "MINIBAR", "SPEC'S", "BIN 365", "WINE & SPIRITS", "STATE STORE", "ABC FINE WINE"]) -> "Expenses:Food:Alcohol"
      contains?(merchant, ["STARBUCKS", "DUNKIN", "PEET'S", "DUTCH BROS", "COFFEE SHOP", "CARIBOU COFFEE", "TIM HORTONS", "BIGGBY", "PHILZ", "BLUE BOTTLE", "INTELLIGENTSIA", "COFFEE BEAN"]) -> "Expenses:Food:Coffee"
      contains?(merchant, ["DOORDASH", "GRUBHUB", "UBER EATS", "POSTMATES", "SEAMLESS", "INSTACART", "SHIPT", "GOPUFF", "CAVIAR", "SLICE"]) -> "Expenses:Food:Delivery"
      contains?(merchant, ["SUBWAY", "FOOD & DRINK", "RESTAURANT", "OTTO TOMOTTOS", ~r/PIZZ/, "GRILL", "DINER", "TAVERN", "BISTRO", "MCDONALD", "CHIPOTLE", "PANERA", "TACO BELL", "WENDY", "CHICK-FIL-A", "FIVE GUYS", "SQ *", "TST*", "TOAST", "SHAKE SHACK", "IN-N-OUT", "WHATABURGER", "SONIC DRIVE", "DAIRY QUEEN", "JACK IN THE BOX", "PANDA EXPRESS", "POPEYES", "KFC", "BURGER KING", "ARBY'S", "ARBYS", "JIMMY JOHN", "JERSEY MIKE", "FIREHOUSE SUBS", "WINGSTOP", "BUFFALO WILD", "APPLEBEE", "OLIVE GARDEN", "OUTBACK", "CHILI'S", "CHILLIS", "RED ROBIN", "CHEESECAKE FACTORY", "DARDEN", "IHOP", "DENNYS", "DENNY'S", "WAFFLE HOUSE", "CRACKER BARREL", "PERKINS", "SUSHI", "RAMEN", "THAI", "INDIAN", "STEAKHOUSE", "SMOKEHOUSE", "BBQ", "BREWERY", "BAR & GRILL", "PUB"]) -> "Expenses:Food:Restaurants"
      contains?(merchant, ["MACYS", "NORDSTROM", "KOHL'S", "NORDSTROM RACK", "TJ MAXX", "MARSHALLS", "ROSS", "H&M", "ZARA", "UNIQLO", "GAP", "OLD NAVY", "NIKE", "ADIDAS", "LULULEMON", "FOOT LOCKER", "VICTORIA'S SECRET", "VICTORIAS SECRET", "ZAPPOS", "DSW", "ALDO", "COACH", "KATE SPADE", "RALPH LAUREN", "CALVIN KLEIN", "TOMMY HILFIGER", "BANANA REPUBLIC", "J.CREW", "JCREW", "EXPRESS", "ANN TAYLOR", "ANNTAYLOR", "ANTHROPOLOGIE", "FREE PEOPLE", "URBAN OUTFITTERS", "AMERICAN EAGLE", "ABERCROMBIE", "HOLLISTER", "PATAGONIA", "REI", "COLUMBIA SPORTSWEAR"]) -> "Expenses:Clothing"
      contains?(merchant, ["SEPHORA", "ULTA", "BATH AND BODY", "GREAT CLIPS", "SUPERCUTS", "SALON", "BARBER", "HAIRCUT", "MASSAGE ENVY", "SPA", "NAIL", "WAXING", "EYEBROW", "SKIN CARE", "DERMSTORE", "GLOSSIER"]) -> "Expenses:Personal Care"
      contains?(merchant, ["BEST BUY", "MICRO CENTER", "APPLE STORE", "ETSY", "TARGET", "WALMART", "STORE", "SHOP", "RETAIL", "OUTLET", "MALL", "WAYFAIR", "OVERSTOCK", "CHEWY", "QVC", "HSN", "BED BATH", "CRATE AND BARREL", "POTTERY BARN", "WILLIAMS SONOMA", "CONTAINER STORE", "DOLLAR TREE", "DOLLAR GENERAL", "FIVE BELOW", "TUESDAY MORNING", "HOME GOODS", "HOMEGOODS", "TJX", "MARSHALLS"]) -> "Expenses:Shopping"
      contains?(merchant, ["PHARMACY", " RX", "CVS", "WALGREENS", "RITE AID", "HOSPITAL", "CLINIC", "DOCTOR", "DENTAL", "VISION", "LABCORP", "QUEST DIAG", "URGENT CARE", "MYCHART", "MD.", "MD ", "D.O.", "D.O "]) -> "Expenses:Medical"
      contains?(merchant, ["PLANET FITNESS", "LA FITNESS", "YMCA", "PELOTON", "GYM", "CROSSFIT"]) -> "Expenses:Health:Fitness"
      contains?(merchant, ["PETCO", "PETSMART", "CHEWY", "VET", "VETERINARY"]) -> "Expenses:Pets"
      contains?(merchant, ["HOME DEPOT", "LOWE'S", "ACE HARDWARE", "IKEA", "WAYFAIR", "MENARDS", "HARDWARE"]) -> "Expenses:Home"
      contains?(merchant, ["JIFFY LUBE", "PEP BOYS", "AUTOZONE", "TAKE 5", "OIL CHANGE", "TIRE", "MEINEKE"]) -> "Expenses:Auto"
      contains?(merchant, ["SHELL", "EXXON", "BP", "CHEVRON", "MOBIL", "SUNOCO", "WAWA FUEL", "7-ELEVEN FUEL", "FUEL", "GAS STATION", "PETRO"]) -> "Expenses:Transportation:Gas"
      contains?(merchant, ["UBER", "LYFT", "TAXI", "CAB"]) -> "Expenses:Transportation:Rideshare"
      contains?(merchant, ["EZPASS", "E-ZPASS", "TOLL", "PARKING", "SPOTHERO", "PARKWHIZ"]) -> "Expenses:Transportation"
      contains?(merchant, ["AMTRAK", "MTA", "NJ TRANSIT", "METRO-NORTH", "BUS TICKET"]) -> "Expenses:Transportation:Transit"
      contains?(merchant, ["VERIZON", "AT&T", "T-MOBILE", "COMCAST", "SPECTRUM", "XFINITY", "INTERNET", "WIFI", "ELECTRIC", "PSEG", "NATIONAL GRID", "WATER", "SEWER", "TRASH", "UTIL ", "UTILITIES", "UTILITY", "DUKE ENERGY", "DOMINION ENERGY", "CON ED", "CONED", "PG&E", "PECO", "EVERSOURCE", "AMEREN", "XCEL ENERGY", "CENTERPOINT", "ENTERGY", "WE ENERGIES", "PIEDMONT", "NICOR", "ATMOS", "COLUMBIA GAS", "WASTE MANAGEMENT", "REPUBLIC SERVICES", "CLEAN HARBORS"]) -> "Expenses:Utilities"
      contains?(merchant, ["GEICO", "PROGRESSIVE", "STATE FARM AUTO", "ALLSTATE AUTO", "CAR INSURANCE", "*AUTO"]) -> "Expenses:Insurance:Car"
      contains?(merchant, ["STATE FARM", "ALLSTATE", "USAA", "LIBERTY MUTUAL", "INSURANCE"]) -> "Expenses:Insurance"
      contains?(merchant, ["USPS", "UPS STORE", "FEDEX", "STAMPS.COM", "POSTAGE"]) -> "Expenses:Postage"
      contains?(merchant, ["AIRBNB", "VRBO", "MARRIOTT", "HILTON", "HYATT", "HOTEL", "AIRLINE", "DELTA", "UNITED AIR", "SOUTHWEST", "JETBLUE", "TSA", "BOOKING.COM", "RITZ-CARLTON", "RITZ CARLTON", "FOUR SEASONS", "W HOTEL", "WESTIN", "SHERATON", "COURTYARD", "RESIDENCE INN", "FAIRFIELD INN", "HAMPTON INN", "HOLIDAY INN", "BEST WESTERN", "DAYS INN", "COMFORT INN", "QUALITY INN", "SLEEP INN", "EXTENDED STAY", "MOTEL", "INN ", "RESORT", "SUITES", "EXPEDIA", "PRICELINE", "KAYAK", "TRIPADVISOR", "TRAVELOCITY", "HOTELS.COM", "SPIRIT AIRLINES", "AMERICAN AIRLINES", "ALASKA AIR", "FRONTIER AIR", "SUN COUNTRY", "AMTRAK TICKET"]) -> "Expenses:Travel"
      contains?(merchant, ["ATM", "WITHDRAWAL"]) -> "Assets:Cash"
      # Bank category fallbacks — used when merchant name alone is not enough
      contains?(bank_category, ["FOOD & DRINK", "FOOD AND DRINK", "DINING", "RESTAURANTS"]) -> "Expenses:Food:Restaurants"
      contains?(bank_category, ["GROCERIES", "SUPERMARKETS"]) -> "Expenses:Food:Groceries"
      contains?(bank_category, ["COFFEE"]) -> "Expenses:Food:Coffee"
      contains?(bank_category, ["TRAVEL", "AIRLINES", "LODGING"]) -> "Expenses:Travel"
      contains?(bank_category, ["GAS", "FUEL"]) -> "Expenses:Transportation:Gas"
      contains?(bank_category, ["RIDESHARE", "TAXI"]) -> "Expenses:Transportation:Rideshare"
      contains?(bank_category, ["HEALTH & WELLNESS", "HEALTH AND WELLNESS", "MEDICAL", "PHARMACY"]) -> "Expenses:Medical"
      contains?(bank_category, ["FITNESS"]) -> "Expenses:Health:Fitness"
      contains?(bank_category, ["ENTERTAINMENT"]) -> "Expenses:Entertainment"
      contains?(bank_category, ["SHOPPING"]) -> "Expenses:Shopping"
      contains?(bank_category, ["PERSONAL CARE", "BEAUTY"]) -> "Expenses:Personal Care"
      contains?(bank_category, ["HOME IMPROVEMENT"]) -> "Expenses:Home"
      contains?(bank_category, ["UTILITIES"]) -> "Expenses:Utilities"
      contains?(bank_category, ["INSURANCE"]) -> "Expenses:Insurance"
      contains?(bank_category, ["CLOTHING", "APPAREL"]) -> "Expenses:Clothing"
      contains?(bank_category, ["PETS"]) -> "Expenses:Pets"
      true -> nil
    end
  end

  def known_account(_, _), do: nil

  defp contains?(merchant, patterns) do
    Enum.any?(patterns, fn
      %Regex{} = pattern -> Regex.match?(pattern, merchant)
      string -> String.contains?(merchant, string)
    end)
  end

  defp blank_as_unknown(value) when value in [nil, ""], do: "unknown"
  defp blank_as_unknown(value), do: value
end
