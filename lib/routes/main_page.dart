import 'dart:io';

import 'package:animations/animations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:outline_material_icons/outline_material_icons.dart';
import 'package:potato_notes/data/dao/note_helper.dart';
import 'package:potato_notes/data/database.dart';
import 'package:potato_notes/data/model/saved_image.dart';
import 'package:potato_notes/internal/colors.dart';
import 'package:potato_notes/internal/custom_icons.dart';
import 'package:potato_notes/internal/device_info.dart';
import 'package:potato_notes/internal/global_key_registry.dart';
import 'package:potato_notes/internal/illustrations.dart';
import 'package:potato_notes/internal/in_app_update.dart';
import 'package:potato_notes/internal/locale_strings.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/shared_prefs.dart';
import 'package:potato_notes/internal/sync/image/image_service.dart';
import 'package:potato_notes/internal/sync/sync_routine.dart';
import 'package:potato_notes/internal/utils.dart';
import 'package:potato_notes/routes/login_page.dart';
import 'package:potato_notes/routes/note_page.dart';
import 'package:potato_notes/routes/search_page.dart';
import 'package:potato_notes/routes/settings_page.dart';
import 'package:potato_notes/routes/setup/setup_page.dart';
import 'package:potato_notes/widget/accented_icon.dart';
import 'package:potato_notes/widget/account_info.dart';
import 'package:potato_notes/widget/drawer_list.dart';
import 'package:potato_notes/widget/drawer_list_tile.dart';
import 'package:potato_notes/widget/fake_fab.dart';
import 'package:potato_notes/widget/note_search_delegate.dart';
import 'package:potato_notes/widget/note_view.dart';
import 'package:potato_notes/widget/notes_logo.dart';
import 'package:potato_notes/widget/selection_bar.dart';
import 'package:potato_notes/widget/tag_editor.dart';

class MainPage extends StatefulWidget {
  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with TickerProviderStateMixin {
  AnimationController controller;
  GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
  ScrollController scrollController = ScrollController();

  ReturnMode mode = ReturnMode.NORMAL;
  int tagIndex = 0;
  bool selecting = false;
  List<Note> selectionList = [];

  Map<ReturnMode, List<Note>> cachedNotesMap = {
    ReturnMode.NORMAL: [],
    ReturnMode.ARCHIVE: [],
    ReturnMode.TRASH: [],
    ReturnMode.FAVOURITES: [],
    ReturnMode.TAG: [],
  };

  @override
  void initState() {
    controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 200),
      reverseDuration: Duration(milliseconds: 100),
      value: 1,
    );

    if (!DeviceInfo.isDesktopOrWeb) {
      appInfo.quickActions.initialize((shortcutType) async {
        switch (shortcutType) {
          case 'new_text':
            newNote();
            break;
          case 'new_image':
            newImage(ImageSource.gallery);
            break;
          case 'new_drawing':
            newDrawing();
            break;
          case 'new_list':
            newList();
            break;
        }
      });
    }

    InAppUpdater.checkForUpdate(context);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // unfortunately we gotta init sharedPrefs here manually cuz normal preferences aren't ready at this point
      final sharedPrefs = await SharedPrefs.newInstance();

      bool welcomePageSeenV2 = await sharedPrefs.getWelcomePageSeen();
      if (!welcomePageSeenV2) {
        Utils.showSecondaryRoute(
          context,
          SetupPage(),
          allowGestures: false,
          barrierDismissible: false,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
        );
      }
    });

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    EdgeInsets padding = EdgeInsets.fromLTRB(
      4,
      4 + MediaQuery.of(context).padding.top + 56,
      4,
      4,
    );
    Animation<double> fade =
        Tween<double>(begin: 0.3, end: 1).animate(controller);

    double fixedDrawerSize;

    if (deviceInfo.uiType == UiType.LARGE_TABLET) {
      fixedDrawerSize = MediaQuery.of(context).size.width / 4;
    } else if (deviceInfo.uiType == UiType.DESKTOP) {
      fixedDrawerSize = MediaQuery.of(context).size.width / 5;
    } else {
      fixedDrawerSize = 64;
    }

    return Row(
      children: <Widget>[
        Visibility(
          visible: deviceInfo.isLandscape,
          child: Material(
            child: SizedBox(
              width: fixedDrawerSize,
              child: getDrawer(deviceInfo.uiSizeFactor >= 4, true),
            ),
          ),
        ),
        Expanded(
          child: Scaffold(
            key: scaffoldKey,
            appBar: selecting
                ? SelectionBar(
                    scaffoldKey: scaffoldKey,
                    selectionList: selectionList,
                    onCloseSelection: () => setState(() {
                      selecting = false;
                      selectionList.clear();
                    }),
                    currentMode: mode,
                  )
                : AppBar(
                    title:
                        Text(Utils.getNameFromMode(mode, tagIndex: tagIndex)),
                    textTheme: Theme.of(context).textTheme,
                    actions: appBarButtons,
                  ),
            body: StreamBuilder<List<Note>>(
              stream: helper.noteStream(mode),
              initialData: cachedNotesMap[mode],
              builder: (context, snapshot) {
                Widget child;
                List<Note> notes = mode == ReturnMode.TAG
                    ? snapshot.data
                        .where(
                          (note) =>
                              note.tags.tagIds
                                  .contains(prefs.tags[tagIndex].id) &&
                              !note.archived &&
                              !note.deleted,
                        )
                        .toList()
                    : snapshot.data ?? [];

                if (snapshot.connectionState == ConnectionState.waiting) {
                  notes = cachedNotesMap[mode];
                } else if (snapshot.connectionState == ConnectionState.active) {
                  cachedNotesMap[mode] = notes;
                }

                if (notes.isNotEmpty) {
                  if (prefs.useGrid) {
                    child = StaggeredGridView.countBuilder(
                      crossAxisCount: deviceInfo.uiSizeFactor,
                      itemBuilder: (context, index) => commonNote(notes[index]),
                      staggeredTileBuilder: (index) => StaggeredTile.fit(1),
                      itemCount: notes.length,
                      controller: scrollController,
                      padding: padding,
                      physics: const AlwaysScrollableScrollPhysics(),
                    );
                  } else {
                    child = ListView.builder(
                      itemBuilder: (context, index) => commonNote(notes[index]),
                      itemCount: notes.length,
                      controller: scrollController,
                      padding: padding,
                      physics: const AlwaysScrollableScrollPhysics(),
                    );
                  }
                } else {
                  child = SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          minHeight: MediaQuery.of(context).size.height),
                      child: Illustrations.quickIllustration(
                        context,
                        getInfoOnCurrentMode.key,
                        getInfoOnCurrentMode.value,
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  child: FadeScaleTransition(
                    animation: fade,
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height,
                      child: child,
                    ),
                  ),
                  onRefresh: sync,
                  displacement: MediaQuery.of(context).padding.top + 40,
                );
              },
            ),
            extendBodyBehindAppBar: true,
            floatingActionButton:
                mode == ReturnMode.NORMAL && !selecting ? fab : null,
            floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
            drawer: !deviceInfo.isLandscape && !selecting
                ? Drawer(
                    child: getDrawer(true, false),
                  )
                : null,
            drawerScrimColor: Colors.transparent,
            drawerEdgeDragWidth: MediaQuery.of(context).size.width,
          ),
        ),
      ],
    );
  }

  Widget getDrawer(bool extended, bool fixed) {
    Color notesLogoPenColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.grey[900];

    return SafeArea(
      child: DrawerList(
        items: Utils.getDestinations(mode),
        secondaryItems: List.generate(prefs.tags.length, (index) {
          Color color = prefs.tags[index].color != 0
              ? Color(NoteColors.colorList[prefs.tags[index].color].color)
              : null;

          return DrawerListItem(
            icon: Icon(MdiIcons.tagOutline),
            selectedIcon: Icon(MdiIcons.tag),
            label: prefs.tags[index].name,
            color: color,
            selectedColor: color,
          );
        }),
        secondaryItemsFooter: DrawerListTile(
          icon: Icon(Icons.add),
          title: LocaleStrings.common.tagNew,
          onTap: () {
            Utils.showNotesModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (context) => TagEditor(
                onSave: (tag) {
                  Navigator.pop(context);
                  tagHelper.saveTag(Utils.markTagChanged(tag));
                },
              ),
            );
          },
          showTitle: extended,
        ),
        header: extended
            ? Container(
                height: 64,
                padding: EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    NotesLogo(penColor: notesLogoPenColor),
                    SizedBox(width: 16),
                    Text(
                      "PotatoNotes",
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        color: Theme.of(context).iconTheme.color,
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              )
            : Container(
                width: 64,
                alignment: Alignment.center,
                child: NotesLogo(penColor: notesLogoPenColor),
              ),
        footer: DrawerListTile(
          icon: Icon(CustomIcons.settings_outline),
          title: LocaleStrings.mainPage.settings,
          onTap: () {
            if (!fixed) {
              Navigator.pop(context);
            }

            Utils.showSecondaryRoute(
              context,
              SettingsPage(),
            );
          },
          showTitle: extended,
        ),
        currentIndex: mode == ReturnMode.TAG ? tagIndex + 4 : mode.index - 1,
        onTap: (index) async {
          if (!fixed) {
            Navigator.pop(context);
          }

          await controller.animateBack(0);
          setState(() {
            selecting = false;
            selectionList.clear();
            mode = ReturnMode.values[index + 1];
          });
          controller.animateTo(1);
        },
        onSecondaryTap: (index) async {
          if (!fixed) {
            Navigator.pop(context);
          }

          await controller.animateBack(0);
          setState(() {
            selecting = false;
            selectionList.clear();
            mode = ReturnMode.TAG;
            tagIndex = index;
          });
          controller.animateTo(1);
        },
        showTitles: extended,
      ),
    );
  }

  Widget get fab {
    return Hero(
      tag: "fabMenu",
      child: FakeFab(
        controller: scrollController,
        onLongPress: () => Utils.showFabMenu(context, fabOptions),
        key: GlobalKeyRegistry.get("fab"),
        shape: StadiumBorder(),
        onTap: () => newNote(),
        child: Icon(OMIcons.edit),
      ),
    );
  }

  List<Widget> get fabOptions {
    return [
      ListTile(
        leading: AccentedIcon(OMIcons.edit),
        title: Text(
          LocaleStrings.common.newNote,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () {
          Navigator.pop(context);

          newNote();
        },
      ),
      ListTile(
        leading: AccentedIcon(MdiIcons.checkboxMarkedOutline),
        title: Text(
          LocaleStrings.common.newList,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () {
          Navigator.pop(context);

          newList();
        },
      ),
      ListTile(
        leading: AccentedIcon(OMIcons.image),
        title: Text(
          LocaleStrings.common.newImage,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => newImage(ImageSource.gallery, shouldPop: true),
        enabled: !DeviceInfo.isDesktopOrWeb,
      ),
      ListTile(
        leading: AccentedIcon(OMIcons.brush),
        title: Text(
          LocaleStrings.common.newDrawing,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () {
          Navigator.pop(context);

          newDrawing();
        },
        enabled: !DeviceInfo.isDesktopOrWeb,
      ),
    ];
  }

  void newNote() async {
    int currentLength = (await helper.listNotes(ReturnMode.NORMAL)).length;

    await Utils.showSecondaryRoute(
      context,
      NotePage(),
    );

    List<Note> notes = await helper.listNotes(ReturnMode.NORMAL);
    int newLength = notes.length;

    if (newLength > currentLength) {
      Note lastNote = notes.last;

      if (lastNote.title.isEmpty &&
          lastNote.content.isEmpty &&
          lastNote.listContent.content.isEmpty &&
          lastNote.images.data.isEmpty &&
          lastNote.reminders.reminders.isEmpty) {
        Utils.deleteNotes(
          scaffoldKey: scaffoldKey,
          notes: [lastNote],
          reason: LocaleStrings.mainPage.deletedEmptyNote,
        );
      }
    }
  }

  void newImage(ImageSource source, {bool shouldPop = false}) async {
    Note note = Utils.emptyNote;
    PickedFile image = await ImagePicker().getImage(source: source);

    if (image != null) {
      SavedImage savedImage =
          await ImageService.loadLocalFile(File(image.path));
      note.images.data.add(savedImage);

      if (shouldPop) Navigator.pop(context);
      note = note.copyWith(id: Utils.generateId());

      Utils.showSecondaryRoute(
        context,
        NotePage(
          note: note,
        ),
      );

      helper.saveNote(Utils.markNoteChanged(note));
    }
  }

  void newList() {
    Utils.showSecondaryRoute(
      context,
      NotePage(
        openWithList: true,
      ),
    );
  }

  void newDrawing() {
    Utils.showSecondaryRoute(
      context,
      NotePage(
        openWithDrawing: true,
      ),
    );
  }

  MapEntry<Widget, String> get getInfoOnCurrentMode {
    switch (mode) {
      case ReturnMode.ARCHIVE:
        return MapEntry(
          appInfo.emptyArchiveIllustration,
          LocaleStrings.mainPage.emptyStateArchive,
        );
      case ReturnMode.TRASH:
        return MapEntry(
          appInfo.emptyTrashIllustration,
          LocaleStrings.mainPage.emptyStateTrash,
        );
      case ReturnMode.FAVOURITES:
        return MapEntry(
          appInfo.noFavouritesIllustration,
          LocaleStrings.mainPage.emptyStateFavourites,
        );
      case ReturnMode.TAG:
        return MapEntry(
          appInfo.noNotesIllustration,
          LocaleStrings.mainPage.emptyStateTag,
        );
      case ReturnMode.ALL:
      case ReturnMode.NORMAL:
      default:
        return MapEntry(
          appInfo.noNotesIllustration,
          LocaleStrings.mainPage.emptyStateHome,
        );
    }
  }

  Widget commonNote(Note note) {
    GlobalKey key = GlobalKeyRegistry.get(note.id);

    return NoteView(
      key: key,
      note: note,
      onTap: () async {
        if (selecting) {
          setState(() {
            if (selectionList.any((item) => item.id == note.id)) {
              selectionList.removeWhere((item) => item.id == note.id);
              if (selectionList.isEmpty) selecting = false;
            } else {
              selectionList.add(note);
            }
          });
        } else {
          bool status = false;
          if (note.lockNote && note.usesBiometrics) {
            bool bioAuth = await Utils.showBiometricPrompt();

            if (bioAuth)
              status = bioAuth;
            else
              status = await Utils.showPassChallengeSheet(context) ?? false;
          } else if (note.lockNote && !note.usesBiometrics) {
            status = await Utils.showPassChallengeSheet(context) ?? false;
          } else {
            status = true;
          }

          if (status) {
            Utils.showSecondaryRoute(
              context,
              NotePage(
                note: note,
              ),
            );
          }
        }
      },
      onLongPress: () async {
        if (selecting) return;

        setState(() {
          selecting = true;
          selectionList.add(note);
        });
      },
      selected: selectionList.any((item) => item.id == note.id),
    );
  }

  List<Widget> get appBarButtons => [
        IconButton(
          icon: Icon(Icons.search),
          tooltip: LocaleStrings.mainPage.search,
          onPressed: () => Utils.showSecondaryRoute(
            context,
            SearchPage(
              delegate: NoteSearchDelegate(),
            ),
          ),
        ),
        IconButton(
          icon: Icon(OMIcons.person),
          tooltip: LocaleStrings.mainPage.account,
          onPressed: () async {
            bool loggedIn = await SyncRoutine.checkLoginStatus();

            if (loggedIn) {
              Utils.showNotesModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (context) => AccountInfo(),
              );
            } else {
              Utils.showSecondaryRoute(
                context,
                LoginPage(),
              );
            }
          },
        ),
        Visibility(
          visible: mode == ReturnMode.ARCHIVE || mode == ReturnMode.TRASH,
          child: Builder(
            builder: (context) {
              return IconButton(
                icon: Icon(MdiIcons.backupRestore),
                onPressed: () async {
                  List<Note> notes = await helper.listNotes(mode);
                  bool result = await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(LocaleStrings.common.areYouSure),
                      content: Text(
                        mode == ReturnMode.ARCHIVE
                            ? LocaleStrings.mainPage.restorePromptArchive
                            : LocaleStrings.mainPage.restorePromptTrash,
                      ),
                      actions: <Widget>[
                        FlatButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(LocaleStrings.common.cancel),
                        ),
                        FlatButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(LocaleStrings.common.restore),
                        ),
                      ],
                    ),
                  );

                  if (result ?? false) {
                    await Utils.restoreNotes(
                      scaffoldKey: scaffoldKey,
                      notes: notes,
                      reason: LocaleStrings.mainPage
                          .notesRestored(selectionList.length),
                      archive: mode == ReturnMode.ARCHIVE,
                    );
                  }
                },
              );
            },
          ),
        ),
        Visibility(
          visible: mode == ReturnMode.TAG,
          child: IconButton(
            icon: Icon(MdiIcons.tagRemoveOutline),
            onPressed: () async {
              bool result = await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(LocaleStrings.common.areYouSure),
                      content: Text(LocaleStrings.mainPage.tagDeletePrompt),
                      actions: <Widget>[
                        FlatButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(LocaleStrings.common.cancel),
                        ),
                        FlatButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(LocaleStrings.common.delete),
                        ),
                      ],
                    ),
                  ) ??
                  false;

              if (result) {
                List<Note> notes = await helper.listNotes(ReturnMode.ALL);
                for (Note note in notes) {
                  note.tags.tagIds.remove(prefs.tags[tagIndex].id);
                  await helper.saveNote(Utils.markNoteChanged(note));
                }
                await controller.animateBack(0);
                int deletedTagIndex = tagIndex;
                setState(() {
                  if (prefs.tags.length == 1) {
                    mode = ReturnMode.NORMAL;
                  } else if (tagIndex == 0 && prefs.tags.length > 2) {
                    tagIndex++;
                  } else if (tagIndex != 0) {
                    tagIndex--;
                  }
                });
                controller.animateTo(1);
                tagHelper.deleteTag(prefs.tags[deletedTagIndex]);
              }
            },
          ),
        ),
        Visibility(
          visible: mode == ReturnMode.TAG,
          child: IconButton(
            icon: Icon(MdiIcons.pencilOutline),
            onPressed: () {
              Utils.showNotesModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (context) => TagEditor(
                  tag: prefs.tags[tagIndex],
                  onSave: (tag) {
                    Navigator.pop(context);
                    tagHelper.saveTag(Utils.markTagChanged(tag));
                  },
                ),
              );
            },
          ),
        ),
      ];

  Future<void> sync() async {
    await SyncRoutine().syncNotes();
  }
}
