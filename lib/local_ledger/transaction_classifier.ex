defmodule LocalLedger.TransactionClassifier do
  @moduledoc """
  Selects an expense account for a normalized transaction.

  Obvious merchant mappings stay local and deterministic. Unknown merchants are
  sent to the local Laya classifier. Low-confidence answers are returned to
  the caller for user confirmation.
  """

  alias LocalLedger.Transaction

  # Keep the taxonomy in one place. The active account list and Laya's
  # hierarchical choice lists are derived from these definitions so approved
  # category additions cannot be added to one list and forgotten in another.
  @taxonomy [
    {"online", "subscriptions, online services, digital goods, or domain services",
     [
       "Expenses:Online Services:Ebay",
       "Expenses:Online Services:Hulu",
       "Expenses:Online Services:Amazon",
       "Expenses:Online Services:Apple",
       "Expenses:Online Services:Google",
       "Expenses:Online Services:TLD"
     ]},
    {"entertainment", "movies, games, music, or other entertainment", ["Expenses:Entertainment"]},
    {"food", "groceries, restaurants, delivery, coffee, or alcohol",
     [
       "Expenses:Food:Groceries",
       "Expenses:Food:Alcohol",
       "Expenses:Food:Coffee",
       "Expenses:Food:Delivery",
       "Expenses:Food:Restaurants"
     ]},
    {"clothing", "clothing, shoes, or apparel", ["Expenses:Clothing"]},
    {"personal", "personal care, education, gifts, or childcare",
     [
       "Expenses:Personal Care",
       "Expenses:Education",
       "Expenses:Gifts",
       "Expenses:Childcare"
     ]},
    {"shopping", "general retail, books, or merchandise",
     ["Expenses:Shopping", "Expenses:Books"]},
    {"health", "medical care, pharmacies, fitness, or pets",
     [
       "Expenses:Medical",
       "Expenses:Health:Fitness",
       "Expenses:Pets"
     ]},
    {"home_auto", "home goods, housing, hardware, or auto maintenance",
     ["Expenses:Home", "Expenses:Housing", "Expenses:Auto"]},
    {"transportation", "fuel, transit, tolls, parking, or rideshare",
     [
       "Expenses:Transportation:Gas",
       "Expenses:Transportation:Rideshare",
       "Expenses:Transportation:Transit",
       "Expenses:Transportation"
     ]},
    {"bills", "utilities, insurance, postage, travel, interest, fees, or taxes",
     [
       "Expenses:Utilities",
       "Expenses:Insurance:Car",
       "Expenses:Insurance",
       "Expenses:Postage",
       "Expenses:Travel",
       "Expenses:Financial:Interest",
       "Expenses:Financial:Fees",
       "Expenses:Taxes"
     ]},
    {"other", "donations, cash withdrawals, or anything that does not fit elsewhere",
     ["Expenses:Donations", "Expenses:Miscellaneous", "Assets:Cash"]}
  ]

  @group_accounts Map.new(@taxonomy, fn {group, _description, accounts} ->
                    {group, accounts}
                  end)

  @group_criteria Map.new(@taxonomy, fn {group, description, _accounts} ->
                    {group, description}
                  end)

  @accounts Enum.flat_map(@taxonomy, fn {_group, _description, accounts} -> accounts end)

  @spec allowed_accounts() :: [String.t()]
  def allowed_accounts, do: @accounts

  @spec group_criteria() :: map()
  def group_criteria, do: @group_criteria

  @spec accounts_for_group(String.t()) :: [String.t()]
  def accounts_for_group(group), do: Map.get(@group_accounts, group, ["Expenses:Miscellaneous"])

  @spec classify(Transaction.t(), keyword()) ::
          {:ok, %{account: String.t(), confidence: float(), source: atom()}}
          | {:error, String.t()}
  def classify(%Transaction{} = transaction, opts \\ []) do
    case known_account(transaction.description) do
      nil -> LocalLedger.OllamaClient.classify(transaction, opts)
      account -> {:ok, %{account: account, confidence: 1.0, source: :rule}}
    end
  end

  @doc false
  def known_account(description) when is_binary(description) do
    merchant = normalize_merchant(description)

    cond do
      contains?(merchant, ["PAYPAL EBAY SAVMYSERVER"]) ->
        "Expenses:Books"

      contains?(merchant, ["EBAY"]) ->
        "Expenses:Online Services:Ebay"

      contains?(merchant, ["HLU", "HULU"]) ->
        "Expenses:Online Services:Hulu"

      contains?(merchant, ["PRIME VIDEO", "AMZN", "AMAZON", "KINDLE"]) ->
        "Expenses:Online Services:Amazon"

      contains?(merchant, ["APPLE COM", "APL", "ICLOUD", "ITUNES", "APPLE MUSIC"]) ->
        "Expenses:Online Services:Apple"

      contains?(merchant, ["GOOGLE GOOGLE", "GOOGLE STORAGE", "YOUTUBE TV"]) ->
        "Expenses:Online Services:Google"

      contains?(merchant, [
        "NAME-CHEAP",
        "NAMECHEAP",
        "CLOUDFLARE",
        "GODADDY",
        "GO DADDY",
        "PORKBUN",
        "GANDI",
        "HOVER",
        "DYNADOT",
        "NAME.COM",
        "GOOGLE DOMAINS",
        "SQUARESPACE DOMAINS",
        "IONOS",
        "1AND1",
        "NETWORK SOLUTIONS",
        "REGISTER.COM"
      ]) ->
        "Expenses:Online Services:TLD"

      contains?(merchant, ["INTEREST CHARGE", "PURCHASE INTEREST", "CASH ADVANCE INTEREST"]) ->
        "Expenses:Financial:Interest"

      contains?(merchant, [
        "ANNUAL FEE",
        "LATE FEE",
        "FOREIGN TRANSACTION FEE",
        "CASH ADVANCE FEE",
        "BALANCE TRANSFER FEE",
        "SERVICE FEE"
      ]) ->
        "Expenses:Financial:Fees"

      contains?(merchant, ["IRS", "TAX PAYMENT", "PROPERTY TAX", "SALES TAX"]) ->
        "Expenses:Taxes"

      contains?(merchant, [
        "CHARITY",
        "DONATION",
        "RED CROSS",
        "UNICEF",
        "SALVATION ARMY",
        "GOFUNDME"
      ]) ->
        "Expenses:Donations"

      contains?(merchant, ["TUITION", "UNIVERSITY", "COLLEGE", "SCHOOL", "COURSERA", "UDEMY"]) ->
        "Expenses:Education"

      contains?(merchant, ["DAYCARE", "DAY CARE", "CHILDCARE", "KINDERCARE", "NANNY"]) ->
        "Expenses:Childcare"

      contains?(merchant, ["RENT PAYMENT", "RENTAL PAYMENT", "PROPERTY MANAGEMENT", "LANDLORD"]) ->
        "Expenses:Housing"

      contains?(merchant, ["NETFLIX", "DISNEY+", "DISNEY PLUS", "HBO", " MAX"]) ->
        "Expenses:Entertainment"

      contains?(merchant, [
        "SPOTIFY",
        "PANDORA",
        "YOUTUBE PREMIUM",
        "STEAMGAMES",
        "PLAYSTATION",
        "XBOX",
        "NINTENDO",
        "TWITCH",
        "AMC THEATRE",
        "REGAL",
        "CINEMARK",
        "IMAX",
        "MOVIE"
      ]) ->
        "Expenses:Entertainment"

      contains?(merchant, [
        "COSTCO",
        "BJ'S",
        "BJS WHOLESALE",
        "SAM'S CLUB",
        "SAMS CLUB",
        "KROGER",
        "SAFEWAY",
        "WHOLE FOODS",
        "TRADER JOE",
        "PUBLIX",
        "ALDI",
        "WEIS",
        "WEGMANS",
        "H-E-B",
        "ALBERTSONS",
        "FRESH DIRECT",
        "FRESHDIRECT",
        "INSTACART",
        "LIDL",
        "GROCERY",
        "SUPERMARKET"
      ]) ->
        "Expenses:Food:Groceries"

      contains?(merchant, ["TOTAL WINE", "LIQUOR", "BEER STORE", "WINE SHOP", "DRIZLY"]) ->
        "Expenses:Food:Alcohol"

      contains?(merchant, ["STARBUCKS", "DUNKIN", "PEET'S", "DUTCH BROS", "COFFEE SHOP"]) ->
        "Expenses:Food:Coffee"

      contains?(merchant, [
        "DOORDASH",
        "GRUBHUB",
        "UBER EATS",
        "POSTMATES",
        "SEAMLESS",
        "CAVIAR",
        "CHOWNOW",
        "DELIVEROO"
      ]) ->
        "Expenses:Food:Delivery"

      contains?(merchant, [
        "SUBWAY",
        "FOOD & DRINK",
        "RESTAURANT",
        "OTTO TOMOTTOS",
        "PIZZA",
        "GRILL",
        "DINER",
        "TAVERN",
        "BISTRO",
        "MCDONALD",
        "CHIPOTLE",
        "PANERA",
        "TACO BELL",
        "WENDY",
        "CHICK-FIL-A",
        "FIVE GUYS",
        "SHAKE SHACK",
        "OLIVE GARDEN",
        "DOMINO"
      ]) ->
        "Expenses:Food:Restaurants"

      contains?(merchant, [
        "MACYS",
        "NORDSTROM",
        "KOHL'S",
        "NORDSTROM RACK",
        "TJ MAXX",
        "MARSHALLS",
        "ROSS",
        "H&M",
        "ZARA",
        "UNIQLO",
        "GAP",
        "OLD NAVY",
        "NIKE",
        "ADIDAS",
        "LULULEMON",
        "FOOT LOCKER",
        "VICTORIA'S SECRET",
        "VICTORIAS SECRET",
        "ABERCROMBIE",
        "ANTHROPOLOGIE",
        "REI"
      ]) ->
        "Expenses:Clothing"

      contains?(merchant, [
        "SEPHORA",
        "ULTA",
        "BATH AND BODY",
        "GREAT CLIPS",
        "SUPERCUTS",
        "MASSAGE ENVY",
        "DRYBAR",
        "SALON",
        "BARBER",
        "HAIRCUT"
      ]) ->
        "Expenses:Personal Care"

      contains?(merchant, [
        "BEST BUY",
        "MICRO CENTER",
        "APPLE STORE",
        "ETSY",
        "TARGET",
        "WALMART",
        "HOMEGOODS",
        "BED BATH",
        "NORDSTROM RACK"
      ]) ->
        "Expenses:Shopping"

      contains?(merchant, [
        "PHARMACY",
        " RX",
        "CVS",
        "WALGREENS",
        "RITE AID",
        "HOSPITAL",
        "CLINIC",
        "DOCTOR",
        "DENTAL",
        "VISION",
        "OPTUM",
        "TELADOC",
        "LABCORP",
        "QUEST DIAG"
      ]) ->
        "Expenses:Medical"

      contains?(merchant, [
        "PLANET FITNESS",
        "LA FITNESS",
        "YMCA",
        "PELOTON",
        "ORANGETHEORY",
        "CROSSFIT",
        "GYM"
      ]) ->
        "Expenses:Health:Fitness"

      contains?(merchant, ["PETCO", "PETSMART", "CHEWY", "VET", "VETERINARY"]) ->
        "Expenses:Pets"

      contains?(merchant, [
        "HOME DEPOT",
        "LOWE'S",
        "ACE HARDWARE",
        "IKEA",
        "WAYFAIR",
        "MENARDS",
        "LOWES",
        "POTTERY BARN",
        "CRATE AND BARREL",
        "HARDWARE"
      ]) ->
        "Expenses:Home"

      contains?(merchant, [
        "JIFFY LUBE",
        "PEP BOYS",
        "AUTOZONE",
        "TAKE 5",
        "OIL CHANGE",
        "TIRE",
        "MEINEKE",
        "O REILLY",
        "NAPA AUTO",
        "FIRESTONE",
        "CAR WASH"
      ]) ->
        "Expenses:Auto"

      contains?(merchant, [
        "SHELL",
        "EXXON",
        "BP",
        "CHEVRON",
        "MOBIL",
        "SUNOCO",
        "WAWA FUEL",
        "7-ELEVEN FUEL",
        "SPEEDWAY",
        "CIRCLE K",
        "QUIKTRIP",
        "RACETRAC",
        "FUEL",
        "GAS STATION",
        "PETRO"
      ]) ->
        "Expenses:Transportation:Gas"

      contains?(merchant, ["UBER", "LYFT", "TAXI", "YELLOW CAB"]) ->
        "Expenses:Transportation:Rideshare"

      contains?(merchant, [
        "EZPASS",
        "E-ZPASS",
        "TOLL",
        "PARKING",
        "SPOTHERO",
        "PARKWHIZ",
        "HONK"
      ]) ->
        "Expenses:Transportation"

      contains?(merchant, [
        "AMTRAK",
        "MTA",
        "NJ TRANSIT",
        "METRO NORTH",
        "SEPTA",
        "PATH TRAIN",
        "LIRR",
        "BUS TICKET"
      ]) ->
        "Expenses:Transportation:Transit"

      contains?(merchant, [
        "VERIZON",
        "AT&T",
        "T-MOBILE",
        "COMCAST",
        "SPECTRUM",
        "XFINITY",
        "INTERNET",
        "WIFI",
        "ROKU",
        "ELECTRIC",
        "PSEG",
        "NATIONAL GRID",
        "WATER",
        "SEWER",
        "TRASH"
      ]) ->
        "Expenses:Utilities"

      contains?(merchant, [
        "GEICO",
        "PROGRESSIVE",
        "STATE FARM AUTO",
        "ALLSTATE AUTO",
        "CAR INSURANCE",
        "*AUTO"
      ]) ->
        "Expenses:Insurance:Car"

      contains?(merchant, ["STATE FARM", "ALLSTATE", "USAA", "LIBERTY MUTUAL", "INSURANCE"]) ->
        "Expenses:Insurance"

      contains?(merchant, ["USPS", "UPS STORE", "FEDEX", "STAMPS.COM", "POSTAGE"]) ->
        "Expenses:Postage"

      contains?(merchant, [
        "AIRBNB",
        "VRBO",
        "MARRIOTT",
        "HILTON",
        "HYATT",
        "HOTEL",
        "AIRLINE",
        "DELTA",
        "UNITED AIR",
        "SOUTHWEST",
        "JETBLUE",
        "TSA",
        "BOOKING.COM",
        "EXPEDIA",
        "KAYAK",
        "TRIPADVISOR",
        "AMERICAN AIR"
      ]) ->
        "Expenses:Travel"

      contains?(merchant, ["ATM", "WITHDRAWAL"]) ->
        "Assets:Cash"

      true ->
        nil
    end
  end

  def known_account(_), do: nil

  defp contains?(merchant, patterns) do
    merchant = normalize_merchant(merchant)

    Enum.any?(patterns, fn pattern ->
      pattern = normalize_merchant(pattern)
      pattern != "" and Regex.match?(~r/(?:^|\s)#{Regex.escape(pattern)}(?:$|\s)/, merchant)
    end)
  end

  defp normalize_merchant(value) do
    value
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.upcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
