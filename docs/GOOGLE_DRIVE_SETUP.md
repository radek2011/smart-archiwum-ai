# Smart Archiwum AI 0.8 — eksperymentalny eksport PDF na Google Drive

## Co działa
Po zapisaniu skanu lokalnie otwórz **Archiwum** i wybierz ikonę chmury obok PDF. Google OAuth wyświetla zgodę na dostęp do plików utworzonych przez aplikację (zakres `drive.file`). Po zatwierdzeniu PDF jest przesyłany do **Mój dysk**. Kopia w przeglądarce pozostaje bez zmian.

## Konfiguracja w Google Cloud Console
1. Otwórz https://console.cloud.google.com/ i wybierz lub utwórz projekt **Smart Archiwum AI**.
2. **APIs & Services → Library:** wyszukaj **Google Drive API** i kliknij **Enable**.
3. **Google Auth Platform:** ustaw ekran zgody i nazwę aplikacji. Przy statusie testowym dodaj własne konto Google na listę **Test users**.
4. **Clients → Create client → Web application:** wpisz dowolną nazwę.
5. W **Authorized JavaScript origins** dodaj dokładnie:
   `https://radek2011.github.io`
   Nie wpisuj ścieżki `/smart-archiwum-ai/` w polu origin.
6. Skopiuj **Client ID**, którego końcówka to `.apps.googleusercontent.com`. Klient web nie wymaga client secret do przeglądarkowego przepływu tokenów.
7. W Smart Archiwum otwórz Archiwum, kliknij ikonę chmury obok **testowego PDF**, wklej Client ID, a następnie wybierz **Połącz i wyślij**. Jeśli to pierwsze logowanie, zaakceptuj zgodę Google dla właściwego konta.
8. Otwórz https://drive.google.com/ na tym samym koncie i sprawdź plik.

## Bezpieczeństwo i ograniczenia
- Nie wpisuj klucza Gemini ani hasła Google jako OAuth Client ID.
- Client ID jest publicznym identyfikatorem projektu OAuth. Token dostępu jest tymczasowy, nie jest zapisywany w IndexedDB, Cloudflare ani repozytorium.
- Dane trafiają bezpośrednio z przeglądarki do Google Drive. Nie przechodzą przez przygotowanego wcześniej Workera Gemini.
- Jest to **ręczny eksport jednostronny**, nie synchronizacja. Usuwanie lokalnego dokumentu **nie** usuwa kopii z Drive.
- W tej wersji nie ma logowania aplikacyjnego ani kontroli dostępu do lokalnego archiwum. Nie używaj jej do poufnych dokumentów firmowych.
- Zwróć uwagę na limit testowych użytkowników, komunikaty o weryfikacji zgody OAuth i zasady Google Workspace, jeśli konto ma ograniczenia administratora.
- Należy dodać autoryzację, obsługę cyklu życia sesji i strategie duplikatów przed wdrożeniem produkcyjnym.
