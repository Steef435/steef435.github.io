---
layout: post
title: Getting Started with Libpeas Extensions in Vala
date: 2016-01-20
summary: A simple tutorial on how to create an extensible application using libpeas in Vala. Includes extensions written in Vala and Python.
---

If you've been looking for easy ways to make your application extensible using "plugins", surely you must have come across a GObject extensions library called [libpeas](https://wiki.gnome.org/Projects/Libpeas). Its engine can seamlessly load GObject-based extension objects which act as "entry points" to the application. Currently, plugins written in C/Vala (shared object files), Python and Lua are supported.

As a project I'm currently working on (more on that soon) requires a system like this, I decided to take a look. I must say, it took me a while to get it all to up and running. Which is why I decided to write a simple introduction in the hope that the journey will be less painful for others. The end goal is to make a small a Gtk+ window with buttons provided by plugins. The core of the application will be written in Vala, and plugin examples are provided in Python and Vala. Let's get started.

## What you need
- Vala (obviously)
- libpeas
- Gtk+ (to spice the example up a bit)
- Python (optional, for the Python plugin)
	- Python
	- python-gobject
	- gobject-introspection

Do make sure you have the development versions installed too, if your distribution splits library packages.

[Valadoc](http://valadoc.org) contains a great reference for all the libraries used in this post ([libpeas-1.0](http://valadoc.org/#!wiki=libpeas-1.0/index) and [gtk+-3.0](http://valadoc.org/#!wiki=gtk+-3.0/index)

## The structure
For this little tutorial I've poked around a bit in the source code of [gedit](https://wiki.gnome.org/Apps/Gedit), the project where libpeas was first conceived. I had never seen an extensible application up close before, so seeing the structure was a nice aha-moment for me.

Most of gedit is actually a shared library. The library defines basically the whole application. Then there's also a little executable called gedit which doesn't do much more than creating some objects defined in libgedit[^1] to start the main loop. In fact, it's so small it's made of one C file: [gedit.c](https://git.gnome.org/browse/gedit/tree/gedit/gedit.c).

Why is this the case? For an application to be truly extendible, plugins need to be able to deal with its internal objects. Thinking about it like this, it's only logical that extendible applications are basically a library. Of course, not all the internal objects need to be accessible by plugins. To hide an object, simply don't ship the header file defining it or in Vala's case, mark the object as private.

To summarize: one big library compiled into a shared object file which a small launcher application and plugins utilize.

## Part 1: the library
Just so you know: this will be most of the work.

As our application consists of a simple Gtk window, we will define the window here. Furthermore, we will define an interface for the extension objects. For good measure, let's give our little app an original name. Like foo.

{% highlight vala %}
namespace Foo {

	public class Window : Gtk.Window {

		public Gtk.ButtonBox buttons { get; set; }

		private Peas.ExtensionSet extensions { get; set; }

		public Window() {
			this.buttons = new Gtk.ButtonBox(Gtk.Orientation.VERTICAL);
			this.destroy.connect(Gtk.main_quit);

			/* Get the default engine */
			var engine = Peas.Engine.get_default();

			/* Enable the python3 loader */
			engine.enable_loader("python3");

			/* Add the current directory to the search path */
			string dir = Environment.get_current_dir();
			engine.add_search_path(dir, dir);

			/* Create the ExtensionSet */
			extensions = new Peas.ExtensionSet(engine, typeof (Foo.Extension), "window", this);
			extensions.extension_added.connect((info, extension) => {
				(extension as Foo.Extension).activate();
			});
			extensions.extension_removed.connect((info, extension) => {
				(extension as Foo.Extension).deactivate();
			});

			/* Load all the plugins */
			foreach (var plugin in engine.get_plugin_list())
				engine.try_load_plugin(plugin);

			this.add(buttons);
			this.show_all();
		}
	}

	public interface Extension : Object {

		/* This will be set to the window */
		public abstract Window window { get; construct set; }

		/* The "constructor" */
		public abstract void activate();

		/* The "destructor" */
		public abstract void deactivate();
	}
}
{% endhighlight %}

As you can see, in the constructor of `Foo.Window`, a [Peas.Engine](http://valadoc.org/#!api=libpeas-1.0/Peas.Engine) is used to search for plugins in the current directory and load the plugins. A [Peas.ExtensionSet](http://valadoc.org/#!api=libpeas-1.0/Peas.ExtensionSet) takes care of creating extension objects implementing the `Foo.Extension` interface as their plugins are loaded by the engine.

By connecting to the `extension_added` signal of `extensions`, we make sure that after an extension object is created, its `activate` member function is called. By connecting to the `extension_removed` signal, we make sure that the deactivate() member function is called. If you want, you could see a `Foo.Extension`'s `activate` and `deactivate` functions as some sort of constructor and destructor. In `activate` they set their stuff up, add a button to the window, and in `deactivate` they remove the button again.

If you're familiar with GObject-style construction, you'll see that we tell `extensions` to create every extension object with its `window` property set to `this` (the current Foo.Window instance). This way, extensions will have a reference to the window from which they can start messing with the application.

Note that the Python loader has to be explicitly enabled.

Of course you can retrieve way more information about a plugin before (and after) loading it. The variable `plugin` is of the type [Peas.PluginInfo](http://valadoc.org/#!api=libpeas-1.0/Peas.PluginInfo), which, combined with [Peas.Engine.provides_extension](http://valadoc.org/#!api=libpeas-1.0/Peas.Engine.provides_extension) should give you all the info you could wish for.

Save the file as foo.vala and create the library:

{% highlight sh %}
# Generate shared object file, C headers, vapi file and gir file
valac -o libfoo.so --library foo -H foo.h  --gir Foo-1.0.gir  -X -shared -X -fPIC --pkg libpeas-1.0 --pkg gtk+-3.0 foo.vala

# Compile typelib file (Python and Lua)
g-ir-compiler --shared-library libfoo Foo-1.0.gir -o Foo-1.0.typelib
{% endhighlight %}

What we get:

- A shared object file compiled from the library
- A vapi file for Vala plugins and the launcher
- A C header file for C and Vala plugins and the launcher
- A GObject introspection file to compile...
- ...a typelib file for Lua and Python plugins

## Part 2: the launcher
Next, we create a launch point for our application. The contents of the file should be pretty straightforward:

{% highlight vala %}
void main(string[] args) {
	Gtk.init(ref args);

	var window = new Foo.Window();

	Gtk.main();
}
{% endhighlight %}

That's all. Save it to a file called launcher.vala and compile it to the executable foo:

{% highlight sh %}
valac -o foo launcher.vala --vapidir . --pkg gtk+-3.0 --pkg foo -X -I. -X -L. -X -lfoo
{% endhighlight %}

The extra options are to make sure our library files can be found while they're not installed in a default search directory.

If you already tried to run the launcher, chances are you've run into this error message:

> ./foo: error while loading shared libraries: libfoo.so: cannot open shared object file: No such file or directory

Because the shared object file isn't installed properly but is located in the current directory, in order to run the launcher, the environment variable `LD_LIBRARY_PATH` needs to be set to the current directory. For the Python plugin, our typelib file also needs to be found in the current directory using `GI_TYPELIB_PATH`:

{% highlight sh %}
export LD_LIBRARY_PATH=.
export GI_TYPELIB_PATH=.
{% endhighlight %}

Now you should be able to run the launcher using `./foo`. An empty window, great!

## Part 3: plugins
Finally, let's write some plugins! Libpeas plugins consist of at least two files: the actual plugin (a shared object file or a script) and a plugin file containing some information about the plugin. Let's start off by writing a plugin in Vala.

### Vala
{% highlight vala %}
class ValaExtension : Object, Foo.Extension {

	public Foo.Window window { get; construct set; }

	Gtk.Button button;

	void activate() {
		button = new Gtk.Button.with_label("Say Hello");

		/* Change label when clicked */
		button.clicked.connect(() => {
			button.set_label("Hello World!");
		});

		/* The magic, it's happening! */
		window.buttons.add(button);
		button.show();
	}

	void deactivate() {
		window.buttons.remove(button);
	}
}

/* Register extension types */
[ModuleInit]
public void peas_register_types(TypeModule module) {
	var objmodule = module as Peas.ObjectModule;

	objmodule.register_extension_type(typeof (Foo.Extension), typeof (ValaExtension));
}
{% endhighlight %}

A few remarks:

- Notice how the extension object is derived from `Foo.Extension`. `window` points to the actual window object because the property is set on construction by the `Peas.ExtensionSet` (using [Peas.Engine.create_extension](http://valadoc.org/#!api=libpeas-1.0/Peas.Engine.create_extension)).
- libpeas uses [GObject-style construction](https://wiki.gnome.org/Projects/Vala/Tutorial#GObject-Style_Construction). Reading up on how it works would make you understand better how these construction properties work. If you want to define a constructor, use a `construct {}` block.
- Shared-object-file-based plugins (C/Vala) require a `peas_register_type` function (don't forget the leading `[ModuleInit]` to register the extension types.

Save the file as vala-extension.vala and compile it to libvala-extension.so using:

{% highlight sh %}
valac -o libvala-extension.so --library vala-extension vala-extension.vala -X -shared -X -fPIC --vapidir . --pkg libpeas-1.0 --pkg gtk+-3.0 --pkg foo -X -I. -X -L. -X -lfoo
{% endhighlight %}

Time to write a plugin file. This is written in the KeyFile format. For all the options, see [the reference](https://developer.gnome.org/libpeas/stable/PeasPluginInfo.html). Note that all this information will be accessible through [Peas.PluginInfo](http://valadoc.org/#!api=libpeas-1.0/Peas.PluginInfo).

{% highlight ini %}
[Plugin]
Module=vala-extension.so
Name=Say Hello
Description=Displays "Hello World!" on click
{% endhighlight %}

Notice how in the Module value, the preceding "lib" is omitted.

Great! Save it to `vala-extension.plugin` and run the launcher. You should see a window with the button we just defined in it.

### Python
Next, let's add a button to quit the application, this time in Python. I'm not going to show how Python and python-gobject work (wish I could! If I did it wrong, please let me know) here, so I'll keep it short.

{% highlight python %}
from gi.repository import GObject
from gi.repository import Peas
from gi.repository import Gtk
from gi.repository import Foo

class PythonExtension(GObject.Object, Foo.Extension):
	window = GObject.Property(type=Foo.Window)
	button = GObject.Property(type=Gtk.Button)

	def do_activate(self):
		self.button = Gtk.Button(label="Quit")
		self.button.connect("clicked", Gtk.main_quit)

		self.window.get_buttons().add(self.button)
		self.button.show()

	def do_deactivate(self):
		self.window.get_buttons().remove(self.button)
{% endhighlight %}

Save it as python-extension.py.

The complementary plugin file (notice how ".py" is omitted):

{% highlight ini %}
[Plugin]
Module=python-extension
Loader=python3
Name=Quit button
{% endhighlight %}

Save it to a .plugin file like you're used to, and enjoy the quit button. Don't forget to set `GI_TYPELIB_PATH` to the current directory (`export GI_TYPELIB_PATH=.`).

## Final words
Well, that's it! I hope this gave you a good impression of what libpeas can do for your application and how to achieve it. Of course, it can do way more. Plugins can bring extra datafiles and GSettings, for example, and libpeas-gtk provides widgets to manage plugins easily. If you want to know more about libpeas, a good starting point would be [the official reference](https://developer.gnome.org/libpeas/stable/). Other sources I used to write this post are:

- [The Vala Tutorial](https://wiki.gnome.org/Projects/Vala/Tutorial)
- [gedit's source code](https://git.gnome.org/browse/gedit/)
- [Valadoc on libpeas](http://valadoc.org/#!wiki=libpeas-1.0/index)
- [Gedit 3 Plugin Sample (Vala)](https://wiki.gnome.org/Projects/Vala/Gedit3PluginSample)
- [libpeas demo source code](https://git.gnome.org/browse/libpeas/tree/peas-demo)

Thanks for reading! If you have any questions or other feedback, please let me know.

[^1]: Check out libgedit's Vala bindings [here](http://valadoc.org/#!wiki=gedit/index).
