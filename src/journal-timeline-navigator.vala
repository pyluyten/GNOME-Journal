/*
 * Copyright (c) 2012 Stefano Candori <scandori@gnome.org>
 *
 * GNOME Journal is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 *
 * GNOME Journal is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with Gnome Journal; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 * Author: Stefano Candori <scandori@gnome.org>
 *
 */

using Gtk;

enum RangeType {
    MORE,
    YEAR,
    MONTH,
    WEEK,
    LAST_WEEK,
    DAY
}

private class Journal.TimelineNavigator : Frame {
    private TreeStore model;
    private TreeView view;
    
    private Gee.List<DateTime?> days_list;
    private TreeRowReference? expanded_week_row;
    private Gee.List<string> expanded_rows;
    private uint expand_timeout;
    private TreeRowReference? selected_day_row;
    private bool show_more;
    
    private ScrolledWindow scrolled_window;
    
    public signal void go_to_date (DateTime date, RangeType type);

    public TimelineNavigator (Orientation orientation, ActivityModel activity_model){
        Object ();
        this.get_style_context ().add_class (STYLE_CLASS_SIDEBAR);
        scrolled_window = new ScrolledWindow (null, null);
        scrolled_window.set_policy (PolicyType.NEVER, PolicyType.AUTOMATIC);
        
        model = new TreeStore (3, typeof (DateTime), // Date
                                  typeof (string),   // String repr. of the Date
                                  typeof (RangeType));  // RangeType type (used for padding)
        view = new TreeView ();
        model.set_sort_func (0, (model, a,b) => {
            Value f;
            Value s;
            model.get_value (a, 0, out f);
            model.get_value (b, 0, out s);
            DateTime first = f as DateTime;
            DateTime second = s as DateTime;
            return first.compare (second);
        });
        model.set_sort_column_id (0, SortType.DESCENDING);
        
        view.motion_notify_event.connect (on_motion_notify);
        view.leave_notify_event.connect (on_leave_notify);
        
        expanded_week_row = null;
        expanded_rows = new Gee.ArrayList<string> ();
        expand_timeout = 0;
        selected_day_row = null;
        show_more = true;
        
        setup_ui ();
        set_events_count (activity_model.days_list);
    }
    
    private void try_collapse_rows (TreePath? path) {
        var to_be_removed = new Gee.ArrayList<string> ();
        foreach (string p in expanded_rows) {
            var path_ = new TreePath.from_string (p);
            if (path != null && path.is_descendant (path_))
                continue;
            if (!selected_day_row.get_path ().is_descendant (path_)) {
                view.collapse_row (path_);
                to_be_removed.add (p);
                foreach (string p2 in expanded_rows)
                    if (p2.has_prefix (p)) {
                        if (to_be_removed.index_of (p2) == -1)
                            to_be_removed.add (p2);
                    }
            }
        }
        foreach (string p in to_be_removed) 
            expanded_rows.remove (p);
    }

    private void on_selection_change () {
        var selection = view.get_selection();
        TreeModel model_f;
        TreeIter iter;
        DateTime date;
        RangeType type;
        if (selection == null)
            return;
        if(selection.get_selected (out model_f, out iter))
        {
            model_f.get(iter, 0, out date, 2, out type);
            try_collapse_rows (null);
            this.go_to_date (date, type);
        }
    }
    
    private void expand_week_row (TreePath path) {
        view.expand_row (path, false);
        //Collapse the previous expanded week row
        if (expanded_week_row != null) {
            if (expanded_week_row.get_path ().compare (path) != 0 && 
                !selected_day_row.get_path ().is_descendant (
                expanded_week_row.get_path ())) {
                view.collapse_row (expanded_week_row.get_path ());
            }
        }
        expanded_week_row = new TreeRowReference (model, path);
        expanded_rows.add (path.to_string ());
    }
    
    private bool on_motion_notify (Gdk.EventMotion event) {
        //Expand weeks on mouse-hover
        TreePath path;
        TreeIter iter;
        DateTime date;
        RangeType type;
        view.get_path_at_pos ((int)event.x, (int)event.y, out path, null, null, null);
        if (path == null)
            return false;
        model.get_iter_from_string (out iter, path.to_string ());
        model.get(iter, 0, out date, 2, out type);
        if (type == RangeType.WEEK || type == RangeType.LAST_WEEK) {
            if (expand_timeout != 0) {
                Source.remove (expand_timeout);
                expand_timeout = 0;
            }
            expand_timeout = 
            Timeout.add (150, () => {
                expand_week_row (path);
                return false;
            });
        }
        else if ((type != RangeType.DAY) || 
                (type == RangeType.DAY && Utils.is_today_or_yesterday (date))){
            if (expand_timeout != 0) {
                Source.remove (expand_timeout);
                expand_timeout = 0;
            }
            if (expanded_week_row != null && 
        !selected_day_row.get_path ().is_descendant (expanded_week_row.get_path ()))
            view.collapse_row (expanded_week_row.get_path ());
        }
        return false;
    }
    
    private bool on_leave_notify (Gdk.EventCrossing event) {
        if (expand_timeout != 0) {
            Source.remove (expand_timeout);
            expand_timeout = 0;
        }
        if (expanded_week_row != null && 
        !selected_day_row.get_path ().is_descendant (expanded_week_row.get_path ()))
            view.collapse_row (expanded_week_row.get_path ());
        
        return false;
    }

    private void setup_ui () {
        view.set_model (model);
        view.show_expanders = false;
        view.level_indentation = 10;
        view.set_headers_visible (false);
        view.set_enable_search(false);
        view.set_rules_hint(false);
        view.set_reorderable(false);
        view.set_enable_tree_lines(false);
        
        var text = new CellRendererText ();
        text.set_alignment (0, 0.5f);
        text.set ("weight", Pango.Weight.BOLD,
                  "height", 30);
        
        var column = new TreeViewColumn ();
        column.pack_start (text, false);
        
        column.set_cell_data_func (text, (layout, cell, model, iter) => {
            RangeType type;
            string name;
            model.get (iter, 1, out name, 2, out type);
            cell.set ("text", name);
            if (type == RangeType.WEEK || type == RangeType.LAST_WEEK) {
                cell.set ("sensitive", false);
            }
            else {
                cell.set ("sensitive", true);
            }
        });
        
        view.append_column (column);
        
        scrolled_window.add_with_viewport (view);
        this.add (scrolled_window);
        
//        model.foreach ((model_, path, year_iter) => {
//            string name;
//            model.get (year_iter, 1, out name);
//            warning(name);
//            return false;
//        });

        var selection = view.get_selection ();
        selection.changed.connect (on_selection_change);
        selection.set_select_function ((selection, model, path, selected) => {
            TreeIter i;
            model.get_iter_from_string (out i, path.to_string ());
            RangeType type;
            model.get (i, 2, out type);
            if (type == RangeType.WEEK || type == RangeType.LAST_WEEK) {
                //Let's select the last day in the week-->first iter in the week
                if (expand_timeout != 0) {
                    Source.remove (expand_timeout);
                    expand_timeout = 0;
                }
                expand_week_row (path);
                
                TreeIter week_iter;
                var next = model.iter_children (out week_iter, i);
                if (next)
                    selection.select_iter (week_iter);
                return false;
            }
            else if (type == RangeType.YEAR || 
                    type == RangeType.MONTH || 
                    type == RangeType.MORE) {
                if (expand_timeout != 0) {
                    Source.remove (expand_timeout);
                    expand_timeout = 0;
                }
                if (path != null) {
                    //FIXME gtk_tree_view_row_expanded doesn't work! why?
                    var i_ = expanded_rows.index_of (path.to_string ());
                    if (i_ != -1) {
                        view.collapse_row (path);
                        expanded_rows.remove (path.to_string ());
                    }
                    else {
                        try_collapse_rows (path);
                        view.expand_row (path, false);
                        expanded_rows.add (path.to_string ());
                    }
                }
                return false;
            }
            else if (type == RangeType.DAY) 
                selected_day_row = new TreeRowReference (model, path);
            return true;
        });
    }
    
    public void set_events_count (Gee.List<DateTime?> days_list) {
        setup_timebar (days_list);
        //Select the first day on start---> Today!
        TreeIter iter;
        var selection = view.get_selection ();
        model.get_iter_first (out iter);
        selection.select_iter (iter);
    }
    
    private void setup_timebar (Gee.List<DateTime?> list) {
        model.clear ();
        days_list = list;
        var today = Utils.get_start_of_today ();
        var tmp = today.add_months (-1);
        var last_month_start = new DateTime.local (tmp.get_year (), 
                                                   tmp.get_month (),
                                                   1, 0, 0, 0);
        int diff_days_last_month = (int)Math.round(((double)(today.difference (last_month_start)) / 
                                   (double)TimeSpan.DAY));
        var this_year_added = false;
        var last_month_added = false;
        var this_month_added = false;
        var last_week_added = false;
        var last_week_start = -1;
        var last_week_end = -1;
        var this_week_added = false;
        var this_week_end = -1;
        var skip_this_week = false;
        var years = new Gee.ArrayList<int> ();
        //Initialize this week and last week range time
        int num = today.get_day_of_week ();
        switch (num) {
            case 1: //Monday
                skip_this_week = true;
                last_week_start = 2; //Two days from today (Saturday)
                last_week_end = 7; //Monday
                break;
            case 2: //Tuesday
                skip_this_week = true;
                last_week_start = 2; //Two days from today (Sunday)
                last_week_end = 8; //Monday
                break;
            default:
                this_week_end = num;
                last_week_start = num + 1;
                last_week_end = last_week_start + 7;
                break;
        }
        foreach (DateTime key in days_list) {
            int diff_days = (int)Math.round(((double)(today.difference (key)) / 
                                             (double)TimeSpan.DAY));
            TreeIter root;
            if (diff_days < 2) {
                switch (diff_days){
                    case 0: 
                        model.append (out root, null);
                        model.set (root, 0, key, 1, _("Today"), 2, RangeType.DAY); 
                        break;
                    case 1:
                        model.append (out root, null);
                        model.set (root, 0, key, 1, _("Yesterday"), 2, RangeType.DAY); 
                        break;
                    default: break;
                }
            }
            else if(!skip_this_week && 
                    diff_days <= this_week_end) {
                if (!this_week_added) {
                    model.append (out root, null);
                    model.set (root, 0, key, 1, _("This week"), 2, RangeType.WEEK);
                    this_week_added = true;
                }
                var next = model.iter_children (out root, null);
                while (next) {
                    RangeType type;
                    model.get (root, 2, out type);
                    if (type == RangeType.WEEK) {
                        TreeIter this_week_iter;
                        model.append (out this_week_iter, root);
                        var text = get_day_representation (key);
                        model.set (this_week_iter, 
                                   0, key, 
                                   1, text, 
                                   2, RangeType.DAY);
                        break;
                    }
                    next = model.iter_next (ref root);
                }
            }else if (diff_days >= last_week_start && 
                       diff_days <= last_week_end) {
                if (!last_week_added) {
                    model.append (out root, null);
                    model.set (root, 0, key, 1, _("Last week"), 2, RangeType.LAST_WEEK);
                    last_week_added = true;
                }
                var next = model.iter_children (out root, null);
                while (next) {
                    RangeType type;
                    model.get (root, 2, out type);
                    if (type == RangeType.LAST_WEEK) {
                        TreeIter last_week_iter;
                        model.append (out last_week_iter, root);
                        var text = get_day_representation (key);
                        model.set (last_week_iter, 
                                   0, key, 
                                   1, text, 
                                   2, RangeType.DAY);
                        break;
                    }
                    next = model.iter_next (ref root);
                }
            } else if (today.get_day_of_month () - last_week_end - 1 > 0) { //This month
                if (!this_month_added) {
                    var this_month = new DateTime.local (today.get_year (), 
                                                         today.get_month (),
                                                         1, 0, 0, 0);
                    model.append (out root, null);
                    var text = this_month.format (_("%B"));
                    model.set (root, 0, this_month, 1, text, 2, RangeType.MONTH);
                    this_month_added = true;
                }
            } else if (diff_days <= diff_days_last_month) { //Last month
                if (!last_month_added) {
                    var new_date = today.add_months (-1);
                    var last_month = new DateTime.local (new_date.get_year (), 
                                                         new_date.get_month (),
                                                         1, 0, 0, 0);
                    model.append (out root, null);
                    var text = last_month.format (_("%B"));
                    model.set (root, 0, last_month, 1, text, 2, RangeType.MONTH);
                    last_month_added = true;
                }
            } else if (diff_days < 365 && show_more) { //Other Months of the year
                if (!this_year_added) {
                    model.append (out root, null);
                    var this_year_date = new DateTime.local (today.get_year (), 1, 1, 0, 0, 0);
                    model.set (root, 0, this_year_date, 1, _("This Year"), 2, RangeType.MORE);
                    this_year_added = true;
                }
            } else { //Other Years
                int year = key.get_year ();
                if (years.index_of (year) == -1) {
                    model.append (out root, null);
                    var year_date = new DateTime.local (key.get_year (), 1, 1, 0, 0, 0);
                    model.set (root, 0, year_date, 
                                     1, key.get_year ().to_string (),
                                     2, RangeType.YEAR);
                    years.add (year);
                }
            }
        }
        foreach (DateTime key in days_list) {
                int diff_days = (int)Math.round(((double)(today.difference (key)) / 
                                                (double)TimeSpan.DAY));
                if (diff_days < last_week_end + 1)
                    continue;
                var year = key.get_year ();
                var month = key.get_month ();
                var week = key.get_week_of_year ();
               
                RangeType type;
                DateTime date;
                var found_year = false;
                var found_month = false;
                var found_near_months = false;
                var found_week = false;
                TreeIter year_iter;
                var next = model.iter_children (out year_iter, null);
                while (next) {
                    model.get (year_iter, 0, out date, 2, out type);
                    if (type == RangeType.MONTH) {
                        //Populate the two nearer month from today!
                        if (date.get_month () == month) {
                            found_near_months = true;
                            TreeIter week_iter;
                            next = model.iter_children (out week_iter, year_iter);
                            while (next) {
                                DateTime w_date;
                                model.get (week_iter, 0, out w_date);
                                var week_ = w_date.get_week_of_year ();
                                if (week_ == week) {
                                    found_week = true;
                                    break;
                                }
                                next = model.iter_next (ref week_iter);
                            }
                            //Add week if not found
                            if (!found_week) {
                                model.append (out week_iter, year_iter);
                                var text = _("Week ") + week.to_string ();
                                model.set (week_iter, 
                                                    0, get_start_of_week (key), 
                                                    1, text,
                                                    2, RangeType.WEEK);
                           }
                           //Add day always
                           TreeIter day_iter;
                           model.append (out day_iter, week_iter);
                           var text = get_day_representation (key);
                           model.set (day_iter, 
                                      0, key, 
                                      1, text,
                                      2, RangeType.DAY);
                           break;
                        }
                    }
                    if (found_near_months)
                        break;
                        
                    if (type == RangeType.YEAR || type == RangeType.MORE) {
                        if (date.get_year () == year) {
                            found_year = true;
                            TreeIter month_iter;
                            next = model.iter_children (out month_iter, year_iter);
                            while (next) {
                                model.get (month_iter, 0, out date, 2, out type);
                                if (date.get_month () == month) {
                                    found_month = true;
                                    TreeIter week_iter;
                                    next = model.iter_children (out week_iter, month_iter);
                                    while (next) {
                                        DateTime w_date;
                                        model.get (week_iter, 0, out w_date);
                                        var week_ = w_date.get_week_of_year ();
                                        if (week_ == week) {
                                            found_week = true;
                                            break;
                                        }
                                        next = model.iter_next (ref week_iter);
                                     }
                                     //Add week if not found
                                     if (!found_week) {
                                        model.append (out week_iter, month_iter);
                                        var text = _("Week ") + week.to_string ();
                                        model.set (week_iter, 
                                                   0, get_start_of_week (key), 
                                                   1, text,
                                                   2, RangeType.WEEK);
                                     }
                                     //Add day always
                                     TreeIter day_iter;
                                     model.append (out day_iter, week_iter);
                                     var text = get_day_representation (key);
                                     model.set (day_iter, 
                                                0, key, 
                                                1, text,
                                                2, RangeType.DAY);
                                     break;
                                }
                                next = model.iter_next (ref month_iter);
                            }
                            //Add month if not found
                            if (!found_month) {
                                model.append (out month_iter, year_iter);
                                var new_date = new DateTime.local (year, month, 1, 0, 0, 0);
                                model.set (month_iter, 
                                           0, new_date, 
                                           1, new_date.format(_("%B")),
                                           2, RangeType.MONTH);
                            }
                            break;
                        }
                    }
                    next = model.iter_next (ref year_iter);
                }
        }
    }
    
    //UTILS
    private string get_day_representation (DateTime date) {
        var text = date.format(_("%a,%e"));
        if (date.get_day_of_month () == 1)
            text += _("st");
        else if (date.get_day_of_month () == 2)
            text += _("nd");
        else if (date.get_day_of_month () == 3)
            text += _("rd");
        else
            text += _("th");
            
        return text;
    }
    
    private DateTime get_start_of_week (DateTime key) {
        //Return a DateTime representing the start of the week in which
        //the argument fall in.
        TimeVal tv;
        Date d = {};
        char[] s = new char[11];
        key.to_timeval (out tv);
        d.set_time_val (tv);
        while (d.get_weekday () != DateWeekday.MONDAY)
            d.subtract_days (1);
        d.strftime (s, "%Y-%m-%d");
        var date = Utils.datetime_from_string ((string)s);
        return date;
    }
}

