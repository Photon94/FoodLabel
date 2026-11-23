# Recipe sharing import

User request: paste a complete “Худеем вместе” sharing message into the QR link field; retain the actual link and retrieve the dish name and КБЖУ. User explicitly authorizes reverse engineering the Android app if necessary.

Use the existing native app and its local database. Support both regular paste into the text field and the Вставить button. Extract a single URL, including the escaped `https\://` spelling. Recognize the supplied share-message title. Automatically fetch only recognized hv.life shared-recipe links; other links remain ordinary QR links. Import explicit source nutrition with its verified basis, preserving the current portion weight. Never estimate nutrition from the name.

Show loading, success and useful failure states, with a retry button. Prevent stale responses from overwriting edits or another food. A failed import must not pair a newly imported name with the previous food’s nutrition. Imported values and the clean QR link use existing draft/save/history persistence. Never print automatically.

Approach: direct native lookup using the recipe-sharing protocol verified from the official Android package. Browser HTML alone redirects to a marketing page; automating a logged-in mobile app would require extra installation and would be less reliable. If the service requires login or does not expose the shared recipe, report that limitation and preserve manual entry rather than inventing data.
