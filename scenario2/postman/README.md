# Day 2 Postman collection

Import `Day2.postman_collection.json` into Postman. Start the stack, then run the folders top to bottom
(folder 1 resets the server). Each request name holds the expected status and error code, and the
collection asserts them automatically. Rebuild after changes: `node scenario2/postman/build-collection.js`.
