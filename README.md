# Smart Archiwum AI – RentSide

Wersja 0.1 – **prototyp interfejsu Android Flutter**, bez rzeczywistych połączeń z Gemini, aparatem i Google Drive.

## Docelowe działanie
1. Skanowanie wielostronicowego dokumentu.
2. Analiza Gemini, transkrypcja oraz tytuł, data i kategorie.
3. Przegląd i zatwierdzenie danych.
4. Generowanie PDF: **analiza AI → pełna transkrypcja → oryginalne fotografie**.
5. Zapis na Google Drive i indeks wyszukiwania semantycznego.

## Aktualny zakres 0.1
- Ekran główny w zatwierdzonym układzie i kolorystyce RentSide; tymczasowy znak wektorowy zamiast oryginalnego pliku logo.
- Zakładki Start, Skanuj, Archiwum, Ustawienia.
- Przyciski prototypowe i wyszukiwanie demonstracyjnych dokumentów.
- Aparat, Gemini, PDF oraz Google Drive nie są jeszcze uruchomione.

## Kompilacja Android
Codemagic → aplikacja `smart-archiwum-ai` → branch `main` → workflow `android-test` → Start new build. Wynikowy artefakt: `app-debug.apk`.

## Bezpieczeństwo
Nie zapisuj klucza Gemini API w repozytorium ani w kodzie aplikacji. Wersja produkcyjna będzie korzystać z backendu z autoryzacją i kontrolą kosztów.
