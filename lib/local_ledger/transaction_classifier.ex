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
    case known_account(transaction.description) do
      nil -> LocalLedger.OllamaClient.classify(transaction, opts)
      account -> {:ok, %{account: account, confidence: 1.0, source: :rule}}
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
  def known_account(description) when is_binary(description) do
    merchant = String.upcase(description)

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
      contains?(merchant, ["COSTCO", "BJ'S", "BJS WHOLESALE", "SAM'S CLUB", "SAMS CLUB", "KROGER", "SAFEWAY", "WHOLE FOODS", "TRADER JOE", "PUBLIX", "ALDI", "WEIS", "WEGMANS", "H-E-B", "ALBERTSONS", "GROCERY", "SUPERMARKET"]) -> "Expenses:Food:Groceries"
      contains?(merchant, ["TOTAL WINE", "LIQUOR", "BEER STORE", "WINE SHOP"]) -> "Expenses:Food:Alcohol"
      contains?(merchant, ["STARBUCKS", "DUNKIN", "PEET'S", "DUTCH BROS", "COFFEE SHOP"]) -> "Expenses:Food:Coffee"
      contains?(merchant, ["DOORDASH", "GRUBHUB", "UBER EATS", "POSTMATES", "SEAMLESS"]) -> "Expenses:Food:Delivery"
      contains?(merchant, ["SUBWAY", "FOOD & DRINK", "RESTAURANT", "OTTO TOMOTTOS", "PIZZA", "GRILL", "DINER", "TAVERN", "BISTRO", "MCDONALD", "CHIPOTLE", "PANERA", "TACO BELL", "WENDY", "CHICK-FIL-A", "FIVE GUYS", "SQ *", "TST*", "TOAST"]) -> "Expenses:Food:Restaurants"
      contains?(merchant, ["MACYS", "NORDSTROM", "KOHL'S", "NORDSTROM RACK", "TJ MAXX", "MARSHALLS", "ROSS", "H&M", "ZARA", "UNIQLO", "GAP", "OLD NAVY", "NIKE", "ADIDAS", "LULULEMON", "FOOT LOCKER", "VICTORIA'S SECRET", "VICTORIAS SECRET"]) -> "Expenses:Clothing"
      contains?(merchant, ["SEPHORA", "ULTA", "BATH AND BODY", "GREAT CLIPS", "SUPERCUTS", "SALON", "BARBER", "HAIRCUT"]) -> "Expenses:Personal Care"
      contains?(merchant, ["BEST BUY", "MICRO CENTER", "APPLE STORE", "ETSY", "TARGET", "WALMART", "STORE", "SHOP", "RETAIL", "OUTLET", "MALL"]) -> "Expenses:Shopping"
      contains?(merchant, ["PHARMACY", " RX", "CVS", "WALGREENS", "RITE AID", "HOSPITAL", "CLINIC", "DOCTOR", "DENTAL", "VISION", "LABCORP", "QUEST DIAG"]) -> "Expenses:Medical"
      contains?(merchant, ["PLANET FITNESS", "LA FITNESS", "YMCA", "PELOTON", "GYM", "CROSSFIT"]) -> "Expenses:Health:Fitness"
      contains?(merchant, ["PETCO", "PETSMART", "CHEWY", "VET", "VETERINARY"]) -> "Expenses:Pets"
      contains?(merchant, ["HOME DEPOT", "LOWE'S", "ACE HARDWARE", "IKEA", "WAYFAIR", "MENARDS", "HARDWARE"]) -> "Expenses:Home"
      contains?(merchant, ["JIFFY LUBE", "PEP BOYS", "AUTOZONE", "TAKE 5", "OIL CHANGE", "TIRE", "MEINEKE"]) -> "Expenses:Auto"
      contains?(merchant, ["SHELL", "EXXON", "BP", "CHEVRON", "MOBIL", "SUNOCO", "WAWA FUEL", "7-ELEVEN FUEL", "FUEL", "GAS STATION", "PETRO"]) -> "Expenses:Transportation:Gas"
      contains?(merchant, ["UBER", "LYFT", "TAXI", "CAB"]) -> "Expenses:Transportation:Rideshare"
      contains?(merchant, ["EZPASS", "E-ZPASS", "TOLL", "PARKING", "SPOTHERO", "PARKWHIZ"]) -> "Expenses:Transportation"
      contains?(merchant, ["AMTRAK", "MTA", "NJ TRANSIT", "METRO-NORTH", "BUS TICKET"]) -> "Expenses:Transportation:Transit"
      contains?(merchant, ["VERIZON", "AT&T", "T-MOBILE", "COMCAST", "SPECTRUM", "XFINITY", "INTERNET", "WIFI", "ELECTRIC", "PSEG", "NATIONAL GRID", "WATER", "SEWER", "TRASH"]) -> "Expenses:Utilities"
      contains?(merchant, ["GEICO", "PROGRESSIVE", "STATE FARM AUTO", "ALLSTATE AUTO", "CAR INSURANCE", "*AUTO"]) -> "Expenses:Insurance:Car"
      contains?(merchant, ["STATE FARM", "ALLSTATE", "USAA", "LIBERTY MUTUAL", "INSURANCE"]) -> "Expenses:Insurance"
      contains?(merchant, ["USPS", "UPS STORE", "FEDEX", "STAMPS.COM", "POSTAGE"]) -> "Expenses:Postage"
      contains?(merchant, ["AIRBNB", "VRBO", "MARRIOTT", "HILTON", "HYATT", "HOTEL", "AIRLINE", "DELTA", "UNITED AIR", "SOUTHWEST", "JETBLUE", "TSA", "BOOKING.COM"]) -> "Expenses:Travel"
      contains?(merchant, ["ATM", "WITHDRAWAL"]) -> "Assets:Cash"
      true -> nil
    end
  end

  def known_account(_), do: nil

  defp contains?(merchant, patterns), do: Enum.any?(patterns, &String.contains?(merchant, &1))

  defp blank_as_unknown(value) when value in [nil, ""], do: "unknown"
  defp blank_as_unknown(value), do: value
end
