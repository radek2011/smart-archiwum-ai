# Smart Archiwum AI 0.6 — Gemini (test)

## Aktualny status
Kod skanera i kod backendu są zapisane. Serwer Gemini **nie został jeszcze wdrożony**, a funkcja wymaga konfiguracji przed pierwszym użyciem.

## Uruchomienie Cloudflare Worker
1. Zaloguj się do Cloudflare → Workers & Pages → Create Worker.
2. W edytorze Workera zastąp kod zawartością pliku `backend/cloudflare-worker.js`.
3. W Worker → Settings → Variables and Secrets skonfiguruj dwa **zaszyfrowane sekrety**:
   - `GEMINI_API_KEY`: prawdziwy klucz Google AI Studio; nigdy nie wklejaj go do Fluttera ani GitHuba.
   - `APP_ACCESS_TOKEN`: długi losowy token dostępu do prywatnego serwera.
4. Wdróż Worker i zanotuj adres HTTPS `*.workers.dev`.
5. Na testowym dokumencie w Smart Archiwum kliknij **Analizuj dokument z Gemini (test)**; wpisz **adres Workera i APP_ACCESS_TOKEN**, a następnie potwierdź przesłanie.
6. Sprawdź proponowaną nazwę, kategorię, datę oraz opis, zanim zatwierdzisz.

## Ważne
- Aktualny frontend GitHub Pages jest publiczny, a Worker używa jednego wspólnego tokenu. To **prototyp**, nie rozwiązanie do dokumentów poufnych ani środowiska produkcyjnego.
- Przed użyciem firmowym należy dodać autoryzację użytkowników, ograniczenia liczby żądań, monitoring kosztów, kontrolę retencji i wymagań RODO oraz właściwe reguły przetwarzania danych u dostawców.
- Token wprowadzany w formularzu nie jest celowo zapisywany w repozytorium ani pamięci trwałej; nie jest to równoznaczne z produkcyjnym zabezpieczeniem dostępu.
- W analizie testowej maksymalnie 5 stron; eksport PDF nadal obsługuje do 30.
- Odmów przesłania dokumentów zawierających dane osobowe lub tajemnice przedsiębiorstwa w testach publicznego prototypu.
