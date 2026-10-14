"""
RecycleGridLayout
=================

.. versionadded:: 1.10.0

.. warning::
    This module is highly experimental, its API may change in the future and
    the documentation is not complete at this time.

The RecycleGridLayout is designed to provide a
:class:`~kivy.uix.gridlayout.GridLayout` type layout when used with the
:class:`~kivy.uix.recycleview.RecycleView` widget. Please refer to the
:mod:`~kivy.uix.recycleview` module documentation for more information.
"""

import itertools
chain_from_iterable = itertools.chain.from_iterable
from kivy.uix.recyclelayout import RecycleLayout
from kivy.uix.gridlayout import GridLayout, GridLayoutException, nmax, nmin
from collections import defaultdict

__all__ = ('RecycleGridLayout', )


class RecycleGridLayout(RecycleLayout, GridLayout):

    _cols_pos = None
    _rows_pos = None

    def __init__(self, **kwargs):
        super(RecycleGridLayout, self).__init__(**kwargs)
        self.funbind('children', self._trigger_layout)

    def on_children(self, instance, value):
        pass

    def _fill_rows_cols_sizes(self):
        cdef list cols = self._cols
        cdef list rows = self._rows
        cdef list cols_sh = self._cols_sh
        cdef list rows_sh = self._rows_sh
        cdef list cols_sh_min = self._cols_sh_min
        cdef list rows_sh_min = self._rows_sh_min
        cdef list cols_sh_max = self._cols_sh_max
        cdef list rows_sh_max = self._rows_sh_max
        self._cols_count = cols_count = [defaultdict(int) for _ in cols]
        self._rows_count = rows_count = [defaultdict(int) for _ in rows]

        # calculate minimum size for each columns and rows
        idx_iter = self._create_idx_iter(len(cols), len(rows))
        cdef bint has_bound_y = False
        cdef bint has_bound_x = False
        
        cdef int col, row
        cdef dict opt
        cdef float w, h
        
        for opt, (col, row) in zip(self.view_opts, idx_iter):
            sh = opt['size_hint']
            shw = sh[0]
            shh = sh[1]
            sz = opt['size']
            w = sz[0]
            h = sz[1]
            sh_min = opt['size_hint_min']
            shw_min = sh_min[0]
            shh_min = sh_min[1]
            sh_max = opt['size_hint_max']
            shw_max = sh_max[0]
            shh_max = sh_max[1]

            if shw is None:
                cols_count[col][w] += 1
            if shh is None:
                rows_count[row][h] += 1

            # compute minimum size / maximum stretch needed
            if shw is None:
                cols[col] = nmax(cols[col], w)
            else:
                cols_sh[col] = nmax(cols_sh[col], shw)
                if shw_min is not None:
                    has_bound_x = True
                    cols_sh_min[col] = nmax(cols_sh_min[col], shw_min)
                if shw_max is not None:
                    has_bound_x = True
                    cols_sh_max[col] = nmin(cols_sh_max[col], shw_max)

            if shh is None:
                rows[row] = nmax(rows[row], h)
            else:
                rows_sh[row] = nmax(rows_sh[row], shh)
                if shh_min is not None:
                    has_bound_y = True
                    rows_sh_min[row] = nmax(rows_sh_min[row], shh_min)
                if shh_max is not None:
                    has_bound_y = True
                    rows_sh_max[row] = nmin(rows_sh_max[row], shh_max)
        self._has_hint_bound_x = has_bound_x
        self._has_hint_bound_y = has_bound_y

    def _update_rows_cols_sizes(self, changed):
        cols_count, rows_count = self._cols_count, self._rows_count
        cdef list cols = self._cols
        cdef list rows = self._rows
        remove_view = self.remove_view
        cdef int n_cols = len(cols)
        cdef int n_rows = len(rows)
        orientation = self.orientation
        
        cdef int index
        cdef float w, h, wn, hn
        cdef int col, row
        cdef float col_w, row_h
        cdef bint was_last_w, was_last_h

        # this can be further improved to reduce re-comp, but whatever...
        for index, widget, (w, h), (wn, hn), sh, shn, sh_min, shn_min, \
                sh_max, shn_max, _, _ in changed:
            if sh != shn or sh_min != shn_min or sh_max != shn_max:
                return True
            elif (sh[0] is not None and w != wn and
                  (h == hn or sh[1] is not None) or
                  sh[1] is not None and h != hn and
                  (w == wn or sh[0] is not None)):
                remove_view(widget, index)
            else:  # size hint is None, so check if it can be resized inplace
                col, row = self._calculate_idx_from_a_view_idx(
                    n_cols, n_rows, index)
                if w != wn:
                    col_w = cols[col]
                    cols_count[col][w] -= 1
                    cols_count[col][wn] += 1
                    was_last_w = cols_count[col][w] <= 0
                    if was_last_w and col_w == w or wn > col_w:
                        return True
                    if was_last_w:
                        del cols_count[col][w]

                if h != hn:
                    row_h = rows[row]
                    rows_count[row][h] -= 1
                    rows_count[row][hn] += 1
                    was_last_h = rows_count[row][h] <= 0
                    if was_last_h and row_h == h or hn > row_h:
                        return True
                    if was_last_h:
                        del rows_count[row][h]

        return False

    def compute_layout(self, data, flags):
        super(RecycleGridLayout, self).compute_layout(data, flags)

        n = len(data)
        smax = self.get_max_widgets()
        if smax and n > smax:
            raise GridLayoutException(
                'Too many children ({}) in GridLayout. Increase rows/cols!'.
                format(n))

        changed = self._changed_views
        if (changed is None or
                changed and not self._update_rows_cols_sizes(changed)):
            return

        self.clear_layout()
        if not self._init_rows_cols_sizes(n):
            self._cols_pos = None
            l, t, r, b = self.padding
            self.minimum_size = l + r, t + b
            return
        self._fill_rows_cols_sizes()
        self._update_minimum_size()
        self._finalize_rows_cols_sizes()

        view_opts = self.view_opts
        for widget, x, y, w, h in self._iterate_layout(n):
            opt = view_opts[n - widget - 1]
            shw, shh = opt['size_hint']
            opt['pos'] = x, y
            wo, ho = opt['size']
            # layout won't/shouldn't change previous size if size_hint is None
            # which is what w/h being None means.
            opt['size'] = [(wo if shw is None else w),
                           (ho if shh is None else h)]

        spacing_x, spacing_y = self.spacing
        cols, rows = self._cols, self._rows

        cols_pos = self._cols_pos = [None, ] * len(cols)
        rows_pos = self._rows_pos = [None, ] * len(rows)

        cols_pos[0] = self.x
        last = cols_pos[0] + self.padding[0] + cols[0] + spacing_x / 2.
        for i, val in enumerate(cols[1:], 1):
            cols_pos[i] = last
            last += val + spacing_x

        last = rows_pos[-1] = \
            self.y + self.height - self.padding[1] - rows[0] - spacing_y / 2.
        n = len(rows)
        for i, val in enumerate(rows[1:], 1):
            last -= spacing_y + val
            rows_pos[n - 1 - i] = last

    def get_view_index_at(self, pos):
        if self._cols_pos is None:
            return 0

        x, y = pos
        col_pos = self._cols_pos
        row_pos = self._rows_pos
        cols, rows = self._cols, self._rows
        if not col_pos or not row_pos:
            return 0

        if x >= col_pos[-1]:
            ix = len(cols) - 1
        else:
            ix = 0
            for val in col_pos[1:]:
                if x < val:
                    break
                ix += 1

        if y >= row_pos[-1]:
            iy = len(rows) - 1
        else:
            iy = 0
            for val in row_pos[1:]:
                if y < val:
                    break
                iy += 1

        if not self._fills_from_left_to_right:
            ix = len(cols) - ix - 1
        if self._fills_from_top_to_bottom:
            iy = len(rows) - iy - 1
        return (iy * len(cols) + ix) if self._fills_row_first else \
            (ix * len(rows) + iy)

    def compute_visible_views(self, data, viewport):
        if self._cols_pos is None:
            return []
        x, y, w, h = viewport
        right = x + w
        top = y + h
        at_idx = self.get_view_index_at
        tl, tr, bl, br = sorted((
            at_idx((x, y)),
            at_idx((right, y)),
            at_idx((x, top)),
            at_idx((right, top)),
        ))

        n = len(data)
        if len({tl, tr, bl, br}) < 4:
            # visible area is one row/column
            return range(min(n, tl), min(n, br + 1))
        indices = []
        stride = len(self._cols) if self._fills_row_first else len(self._rows)
        if stride:
            x_slice = br - bl + 1
            indices = chain_from_iterable(
                range(min(s, n), min(n, s + x_slice))
                for s in range(tl, bl + 1, stride))
        return indices

    def _calculate_idx_from_a_view_idx(self, n_cols, n_rows, view_idx):
        '''returns a tuple of (column-index, row-index) from a view-index'''
        if self._fills_row_first:
            row_idx, col_idx = divmod(view_idx, n_cols)
        else:
            col_idx, row_idx = divmod(view_idx, n_rows)
        if not self._fills_from_left_to_right:
            col_idx = n_cols - col_idx - 1
        if not self._fills_from_top_to_bottom:
            row_idx = n_rows - row_idx - 1
        return (col_idx, row_idx, )

    def goto_view(self, index):
        if self._cols_pos is None or self._rows_pos is None:
            return
        rv = self.recycleview
        if not rv:
            return

        cdef int n_cols = len(self._cols)
        cdef int n_rows = len(self._rows)
        if n_cols == 0 or n_rows == 0:
            return

        cdef int col_idx, row_idx
        col_idx, row_idx = self._calculate_idx_from_a_view_idx(n_cols, n_rows, index)

        if col_idx < 0 or col_idx >= len(self._cols_pos) or row_idx < 0 or row_idx >= len(self._rows_pos):
            return

        cdef float pos_x = self._cols_pos[col_idx]
        cdef float pos_y = self._rows_pos[row_idx]

        if self.width <= rv.width:
            rv.scroll_x = 0
        else:
            rv.scroll_x = max(0.0, min(1.0, pos_x / (self.width - rv.width)))

        if self.height <= rv.height:
            rv.scroll_y = 1.0
        else:
            rv.scroll_y = max(0.0, min(1.0, (pos_y - rv.height) / (self.height - rv.height)))
