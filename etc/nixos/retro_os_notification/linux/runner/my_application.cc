#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk-layer-shell/gtk-layer-shell.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void method_call_handler(FlMethodChannel* channel,
                                 FlMethodCall* method_call,
                                 gpointer user_data) {
  GtkWidget* window = GTK_WIDGET(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "show") == 0) {
    gtk_widget_show(window);
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (strcmp(method, "hide") == 0) {
    gtk_widget_hide(window);
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  if (!monitor) monitor = gdk_display_get_monitor(display, 0);
  GdkRectangle geometry;
  gdk_monitor_get_geometry(monitor, &geometry);

  double scale = (double)geometry.width / 1920.0;
  if (scale < 0.5) scale = 0.5;
  if (scale > 2.0) scale = 2.0;

  int win_w = (int)(316.0 * scale);
  int win_h = (int)(80.0 * scale);
  int margin = (int)(16.0 * scale);

  gtk_window_set_default_size(window, win_w, win_h);

  GdkGeometry hints = {};
  hints.min_width = win_w;
  hints.max_width = win_w;
  hints.min_height = win_h;
  hints.max_height = win_h;
  gtk_window_set_geometry_hints(window, nullptr, &hints,
                                (GdkWindowHints)(GDK_HINT_MIN_SIZE | GDK_HINT_MAX_SIZE));

  if (gtk_layer_is_supported()) {
    // Wayland: layer shell
    gtk_layer_init_for_window(window);
    gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_OVERLAY);
    gtk_layer_set_exclusive_zone(window, 0);
    gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_LEFT, geometry.width - win_w - margin);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, geometry.height - win_h - margin);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_RIGHT, margin);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_BOTTOM, margin);
  } else {
    // X11: posicionamento direto
    gtk_window_set_decorated(window, FALSE);
    gtk_window_set_keep_above(window, TRUE);
    gtk_window_set_skip_taskbar_hint(window, TRUE);
    gtk_window_set_focus_on_map(window, FALSE);
    gtk_window_move(window,
                    geometry.x + geometry.width - win_w - margin,
                    geometry.y + geometry.height - win_h - margin);
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  // Enable RGBA visual for compositor transparency (required on X11; Wayland handles it automatically)
  GdkScreen* screen = gtk_widget_get_screen(GTK_WIDGET(window));
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual) {
    gtk_widget_set_visual(GTK_WIDGET(window), visual);
  }
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color = {0.0, 0.0, 0.0, 0.0};
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  gtk_widget_realize(GTK_WIDGET(view));
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  gtk_widget_show_all(GTK_WIDGET(window));

  // Registra o canal para hide/show da janela GTK a partir do Dart
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "notification_window",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_handler,
                                             GTK_WIDGET(window), nullptr);

  // Começa escondida — Dart chama "show" quando há uma notificação
  gtk_widget_hide(GTK_WIDGET(window));
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
