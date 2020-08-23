import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:potato_notes/data/database.dart';
import 'package:potato_notes/data/model/list_content.dart';
import 'package:potato_notes/internal/colors.dart';
import 'package:potato_notes/internal/utils.dart';
import 'package:potato_notes/widget/note_view_images.dart';
import 'package:potato_notes/widget/note_view_statusbar.dart';
import 'package:rich_text_editor/rich_text_editor.dart';

class NoteView extends StatelessWidget {
  final Note note;
  final SpannableList providedTitleList;
  final SpannableList providedContentList;
  final Function() onTap;
  final Function() onLongPress;
  final bool selected;

  NoteView({
    Key key,
    @required this.note,
    this.providedTitleList,
    this.providedContentList,
    this.onTap,
    this.onLongPress,
    this.selected = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    //String parsedStyleJson = utf8.decode(gzip.decode(note.styleJson.data));
    SpannableList spannableList =
        providedContentList; // ?? SpannableList.fromJson(parsedStyleJson);
    Color borderColor;

    if (selected) {
      if (note.color != 0) {
        borderColor = Theme.of(context).iconTheme.color;
      } else {
        borderColor = Theme.of(context).accentColor;
      }
    } else {
      borderColor = Colors.transparent;
    }

    List<Widget> content = getItems(context, spannableList);

    return Card(
      color: note.color != 0
          ? Color(NoteColors.colorList[note.color].dynamicColor(context))
          : Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardBorderRadius),
        side: BorderSide(
          color: borderColor,
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: selected ? 6 : 2,
      shadowColor: Colors.black.withOpacity(0.5),
      margin: kCardPadding,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(kCardBorderRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IgnorePointer(
              child: Visibility(
                visible:
                    (note.images?.isNotEmpty ?? false) && !note.hideContent,
                child: NoteViewImages(
                  images: note.images,
                  showPlusImages: true,
                  numPlusImages: note.images.length < kMaxImageCount
                      ? 0
                      : note.images.length - kMaxImageCount,
                ),
              ),
            ),
            Visibility(
              visible: content.isNotEmpty,
              child: ListView.separated(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                padding: EdgeInsets.all(16),
                itemBuilder: (context, index) => content[index],
                separatorBuilder: (context, index) {
                  return SizedBox(height: 4);
                },
                itemCount: content.length,
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                width: constraints.maxWidth,
                child: NoteViewStatusbar(
                  note: note,
                  width: constraints.maxWidth,
                  padding: content.isEmpty ? EdgeInsets.all(16) : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> getItems(BuildContext context, SpannableList spannableList) {
    List<Widget> items = [];

    if (note.title != "") {
      items.add(
        providedTitleList != null
            ? RichText(
                text: providedTitleList.toTextSpan(
                  note.title,
                  defaultStyle: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context)
                        .textTheme
                        .caption
                        .color
                        .withOpacity(0.7),
                  ),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : Text(
                note.title ?? "",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context)
                      .textTheme
                      .caption
                      .color
                      .withOpacity(0.7),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
      );
    }

    if ((note.title.isEmpty &&
            note.content.isEmpty &&
            note.listContent.isEmpty &&
            !note.hideContent &&
            note.images.isEmpty) ||
        (note.content.isNotEmpty && !note.hideContent)) {
      items.add(
        spannableList != null
            ? RichText(
                text: spannableList.toTextSpan(
                  note.content,
                  defaultStyle: Theme.of(context).textTheme.bodyText1.copyWith(
                        fontSize: 16,
                        color: Theme.of(context)
                            .textTheme
                            .caption
                            .color
                            .withOpacity(0.5),
                      ),
                ),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              )
            : Text(
                note.content,
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context)
                      .textTheme
                      .caption
                      .color
                      .withOpacity(0.5),
                ),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
      );
    }

    if (note.list && note.listContent.isNotEmpty && !note.hideContent) {
      items.add(
        ListView.separated(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          padding: EdgeInsets.all(0),
          itemBuilder: (context, index) => listContentWidgets[index],
          itemCount: listContentWidgets.length,
          separatorBuilder: (context, index) => SizedBox(height: 4),
        ),
      );
    }

    return items;
  }

  List<Widget> get listContentWidgets => List.generate(
        (note.listContent?.length ?? 0) > 5
            ? 5
            : (note.listContent?.length ?? 0),
        (index) {
          ListItem item = note.listContent[index];

          return LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                children: [
                  Icon(
                    item.status
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    color: item.status
                        ? note.color != 0
                            ? Theme.of(context).textTheme.caption.color
                            : Theme.of(context).accentColor
                        : null,
                    size: 20,
                  ),
                  VerticalDivider(
                    color: Colors.transparent,
                    width: 8,
                  ),
                  SizedBox(
                    width: constraints.maxWidth - 28,
                    child: Text(
                      item.text,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Theme.of(context)
                              .textTheme
                              .caption
                              .color
                              .withOpacity(item.status ? 0.5 : 0.7),
                          decoration:
                              item.status ? TextDecoration.lineThrough : null),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
}
