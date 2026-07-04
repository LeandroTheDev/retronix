#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk-layer-shell/gtk-layer-shell.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)


static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Layer shell — deve ser chamado antes de realize
  g_print("[layer-shell] supported: %d\n", gtk_layer_is_supported());
  gtk_layer_init_for_window(window);
  g_print("[layer-shell] is_layer_window: %d\n", gtk_layer_is_layer_window(window));
  gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_OVERLAY);
  gtk_layer_set_exclusive_zone(window, 0);
  gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);

  // 4 ancoras — KDE requer todas para respeitar tamanho
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);

  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  if (!monitor) monitor = gdk_display_get_monitor(display, 0);
  GdkRectangle geometry;
  gdk_monitor_get_geometry(monitor, &geometry);

  double scale = (double)geometry.width / 1920.0;
  if (scale < 0.5) scale = 0.5;
  if (scale > 2.0) scale = 2.0;

  int win_w = (int)(220.0 * scale);
  int win_h = (int)(80.0 * scale);
  int margin = (int)(16.0 * scale);

  // Margens LEFT e TOP empurram a janela para o canto inferior direito
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_LEFT, geometry.width - win_w - margin);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, geometry.height - win_h - margin);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_RIGHT, margin);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_BOTTOM, margin);

  gtk_window_set_default_size(window, win_w, win_h);

  GdkGeometry hints = {};
  hints.min_width = win_w;
  hints.max_width = win_w;
  hints.min_height = win_h;
  hints.max_height = win_h;
  gtk_window_set_geometry_hints(window, nullptr, &hints,
                                (GdkWindowHints)(GDK_HINT_MIN_SIZE | GDK_HINT_MAX_SIZE));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  gtk_widget_realize(GTK_WIDGET(view));
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  gtk_widget_show_all(GTK_WIDGET(window));
  g_print("[layer-shell] window shown\n");
}

static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
