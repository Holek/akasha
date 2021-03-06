# Changelog

## Version 0.3.0

* Asynchronous event listeners (`AsyncEventRouter`).
* Simplified initialization of event- and command routers.
* Remove dependency on the `http_event_store` gem.
* `Event#metadata` is no longer OpenStruct.

## Version 0.2.0

* Synchronous event listeners (see `examples/sinatra/app.rb`).
* HTTP-based Eventstore storage.


## Version 0.1.0

* Cleaner syntax for adding events to changesets: `changeset.append(:it_happened, foo: 'bar')`.
* Support for command routing (`Akasha::CommandRouter`).


## Version 0.0.1

Initial release, basic functionality.
