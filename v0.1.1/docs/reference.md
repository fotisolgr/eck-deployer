# v0.1.1 API reference

This contains the v0.1.1 API reference.

## GET /v0.1.1/cats

Returns a list of all cats.

## GET /v0.1.1/breeds

Returns a list of all breeds of cats.

## GET /v0.1.1/breeds/:breed_name/cats

Returns a list of all cats under the `:breed_name` breed.

## GET /v0.1.1/search

Parameters:

- `q` = A string containing the search query for a cat name or breed.

Returns a list of cats that match the search query.

## GET /v0.1.1/cat/:name/lives_left

Returns how many lives the cat named `:name` still has left.
