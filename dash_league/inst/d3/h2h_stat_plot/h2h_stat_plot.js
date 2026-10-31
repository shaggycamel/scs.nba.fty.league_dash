// stackedbar.js
// r2d3 script — 100% stacked HORIZONTAL bar chart (ggplot
// geom_col(position = "fill") + coord_flip() equivalent), with:
//   - d3.stackOffsetExpand to normalize each category's bar to 0-1
//   - fixed 50% reference line (vertical)
//   - reversed Set2 palette (scale_fill_brewer("Set2", direction = -1))
//   - per-segment tooltip: hover a single stacked segment to see just
//     that competitor's pre-formatted label string
//
// Layout: categories run top-to-bottom (one horizontal bar per category),
// each bar's 0-1 stack proportion runs left-to-right.
//
// Expected input data shape (one row per name x competitor, long format —
// same shape ggplot/geom_col consumed):
//   [{ name: "...", competitor: "...", value: 0.42, label: "..." }, ...]
//
// Competitor order/names are derived entirely from `data` (first-seen
// order in the array) — no options.competitors override. If you need a
// specific stack/label order, arrange/sort the rows in R before sending,
// e.g. by an ordered factor's level order.
//   height, width, margin : standard sizing overrides

// ---- persistent setup (created once, reused across re-renders) --------

var margin = (options && options.margin) || { top: 60, right: 20, bottom: 30, left: 70 };

var g = svg.select("g.plot-area");
if (g.empty()) {
  svg.style("overflow", "hidden");
  g = svg.append("g").attr("class", "plot-area");
  svg.append("g").attr("class", "category-axis");
  svg.append("line").attr("class", "ref-line")
    .attr("stroke", "#333")
    .attr("stroke-width", 1);
  svg.append("g").attr("class", "competitor-labels");
}

var categoryAxisG = svg.select(".category-axis");
var refLine = svg.select(".ref-line");
var labelsG = svg.select(".competitor-labels");

// Tooltip divs — keyed to this chart's own <svg> DOM node (via properties,
// not random ids) so re-renders reuse the same divs instead of creating new
// ones each time. r2d3 re-runs this whole script on every renderD3() call, so
// anything keyed by Math.random() would otherwise leak a fresh div into
// <body> on every single data update. Two divs are kept so a bar hover can
// show both competitors' labels at once.
var svgNode = svg.node();

function getTooltip(cacheKey) {
  if (svgNode[cacheKey]) return svgNode[cacheKey];

  var el = d3.select("body").append("div")
    .style("position", "absolute")
    .style("pointer-events", "none")
    .style("z-index", "2147483647")
    .style("background", "rgba(255,255,255,0.97)")
    .style("border", "1px solid #ccc")
    .style("border-radius", "4px")
    .style("padding", "6px 10px")
    .style("font-size", "12px")
    .style("box-shadow", "0 1px 4px rgba(0,0,0,0.15)")
    .style("overflow", "hidden")
    .style("white-space", "nowrap")
    .style("transition", "width 180ms ease-out, height 180ms ease-out, opacity 120ms ease-out")
    .style("width", "0px")
    .style("height", "0px")
    .style("opacity", 0);

  svgNode[cacheKey] = el;
  return el;
}

function growTooltip(el, label) {
  var html = label.replace(/\n/g, "<br>");

  // Measure natural size first: set content + auto sizing with opacity 0
  // (invisible, no transition) so offsetWidth/Height reflect the final
  // fully-grown size, not a mid-transition value.
  el
    .style("transition", "none")
    .style("width", "auto")
    .style("height", "auto")
    .style("opacity", 0)
    .html(html);

  var width = el.node().offsetWidth;
  var height = el.node().offsetHeight;

  // Snap back to 0x0 (still untransitioned), then re-enable transitions and
  // grow to the measured size — this is the actual animation.
  el
    .style("width", "0px")
    .style("height", "0px");

  // Force layout flush so the browser registers the 0x0 state before we
  // re-enable transitions and change size again on the next tick.
  el.node().offsetHeight; // eslint-disable-line no-unused-expressions

  el
    .style("transition", "width 180ms ease-out, height 180ms ease-out, opacity 120ms ease-out")
    .style("width", width + "px")
    .style("height", height + "px")
    .style("opacity", 1);

  return { width: width, height: height };
}

function hideTooltip(el) {
  el
    .style("transition", "width 180ms ease-out, height 180ms ease-out, opacity 120ms ease-out")
    .style("opacity", 0)
    .style("width", "0px")
    .style("height", "0px");
}

var tooltip = getTooltip("__r2d3Tooltip");
var tooltipOther = getTooltip("__r2d3TooltipOther");

// This chart animates its own card's height. r2d3 only recalculates on window
// resizes, so nudge it whenever the card's size changes, otherwise the plot
// stays at the collapsed height inside the grown card.
var resizeCard = svgNode.closest(".h2h-plot-card");
if (resizeCard && window.ResizeObserver) {
  if (resizeCard.__cardResizeObserver) resizeCard.__cardResizeObserver.disconnect();
  resizeCard.__cardResizeObserver = new ResizeObserver(function() {
    window.dispatchEvent(new Event("resize"));
  });
  resizeCard.__cardResizeObserver.observe(resizeCard);
}

r2d3.onRender(function(data, svg, width, height, options) {
  // ---- reshape long data into wide (one row per `name`, one column per competitor) ----

  var names = Array.from(new Set(data.map(function(d) { return d.name; })));
  // Competitor order/names come purely from `data` now — no separate
  // options.competitors channel that could desync from the actual rows
  // being rendered. Order is preserved as first-seen in the data array;
  // if `competitor` is an ordered factor in R, sort/arrange df_plt() by
  // that factor before sending so first-seen order matches factor order.
  var competitors = Array.from(new Set(data.map(function(d) { return d.competitor; })));

  // Points leagues send an "overall" row (is_overall) as the first name. It
  // starts collapsed: only that one bar shows, and clicking it reveals the
  // weighted category rows below.
  var overallRows = data.filter(function(d) { return d.is_overall === true; });
  var hasOverall = overallRows.length > 0;
  var overallName = hasOverall ? overallRows[0].name : null;
  var expanded = hasOverall ? !!(options && options.expanded) : true;

  var innerWidth = width - margin.left - (margin.right || 20);
  var innerHeight = height - margin.top - margin.bottom;

  g.attr("transform", "translate(" + margin.left + "," + margin.top + ")");

  var byName = names.map(function(nm) {
    var row = { name: nm };
    var labels = {};
    var negative = {};
    var isOverall = false;
    data.filter(function(d) { return d.name === nm; }).forEach(function(d) {
      // The stack always uses magnitudes; the sign drives the negative-category
      // shade. Category leagues mark lower-is-better categories (e.g. turnovers)
      // explicitly via is_negative.
      row[d.competitor] = Math.abs(d.value);
      negative[d.competitor] = d.is_negative === true || d.value < 0;
      labels[d.competitor] = d.label;
      isOverall = isOverall || d.is_overall === true;
    });
    row.__labels = labels;
    row.__negative = negative;
    row.__overall = isOverall;
    return row;
  });

  var stackGen = d3.stack()
    .keys(competitors)
    .offset(d3.stackOffsetExpand); // normalizes each x-category to sum to 1, matches position="fill"

  var series = stackGen(byName);

  // ---- scales ----
  // Horizontal layout: categories run top-to-bottom (band scale on the
  // vertical axis), 0-1 stack proportion runs left-to-right (linear scale
  // on the horizontal axis). Variable names keep their original meaning
  // (categoryScale, proportionScale) rather than reusing x/y, since their
  // screen orientation no longer matches their old x/y roles.

  var categoryDomain = (hasOverall && !expanded) ? [overallName] : names;

  var categoryScale = d3.scaleBand()
    .domain(categoryDomain)
    .range([0, innerHeight])
    .padding(0.2);

  var proportionScale = d3.scaleLinear()
    .domain([0, 1])
    .range([0, innerWidth]);

  function barY(d) {
    if (hasOverall && !expanded && !d.segment.data.__overall) {
      return categoryScale(overallName) || 0;
    }
    return categoryScale(d.segment.data.name) || 0;
  }

  function barHeight(d) {
    if (hasOverall && !expanded && !d.segment.data.__overall) return 0;
    return categoryScale.bandwidth();
  }

  var color = d3.scaleOrdinal()
    .domain(competitors)
    .range(d3.schemeSet2.slice(0, competitors.length).reverse());

  function fillFor(d) {
    var base = color(d.key);
    var negative = d.segment.data.__negative[d.key];
    return negative ? d3.color(base).darker(0.4).formatHex() : base;
  }

  // ---- axis (categories only — labs(x=NULL, y=NULL) in the original
  // means no proportion-axis numbers are drawn, matching that theme) ----

  function drawAxis() {
    categoryAxisG
      .attr("transform", "translate(" + margin.left + "," + margin.top + ")")
      .call(
        d3.axisLeft(categoryScale)
          .tickSizeOuter(0)
          .tickFormat(function(d) {
            return (hasOverall && d === overallName) ? (expanded ? "▾ " : "▸ ") + d : d;
          })
      );

    categoryAxisG.selectAll(".tick").select("text")
      .style("font-size", function(d) {
        return (hasOverall && d === overallName) ? "13px" : "16px";
      });

    categoryAxisG.selectAll(".tick")
      .style("opacity", function(d) {
        return (expanded || !hasOverall || d === overallName) ? 1 : 0;
      });
  }

  drawAxis();

  // The chart also re-renders on card resizes; only play the reveal when the
  // chart first becomes expanded, not on every resize frame.
  var revealState = (hasOverall && expanded) ? "expanded" : "collapsed";
  var firstExpandedRender = revealState === "expanded" && svgNode.__revealState !== "expanded";

  if (firstExpandedRender) {
    categoryAxisG
      .style("opacity", 0)
      .transition("axis-reveal")
      .duration(600)
      .ease(d3.easeCubicOut)
      .style("opacity", 1);
  }

  // ---- 50% reference line (now vertical, spanning the full height) ----

  refLine
    .attr("y1", margin.top)
    .attr("y2", margin.top + innerHeight)
    .transition().duration(300)
    .attr("x1", margin.left + proportionScale(0.5))
    .attr("x2", margin.left + proportionScale(0.5));

  // ---- competitor name labels: white boxes sitting in the top margin,
  // above all bars (not tied to any single category row). Normally two
  // boxes, horizontally centered at 25% and 75% of the proportion scale.
  // Bye weeks (post-season, no opponent) only have one competitor in the
  // data at all — in that case render a single box centered at 50%
  // instead of duplicating the same name into both slots. ----

  var firstCompetitor = competitors[0];
  var lastCompetitor = competitors[competitors.length - 1];

  var labelBoxData = (competitors.length <= 1)
    ? [{ competitor: firstCompetitor, xFrac: 0.5, anchor: "only" }]
    : [
        { competitor: firstCompetitor, xFrac: 0.25, anchor: "first" },
        { competitor: lastCompetitor, xFrac: 0.75, anchor: "last" }
      ];

  var labelFontSize = 19;
  var labelBoxPadding = 8;
  var labelBoxHeight = 34;
  var labelBoxY = margin.top - labelBoxHeight - 10; // sits in the top margin, 10px above the plot area

  labelsG.attr("transform", "translate(0,0)"); // boxes positioned in absolute svg coords below, not translated with the plot area

  var labelItems = labelsG.selectAll("g.competitor-label")
    .data(labelBoxData, function(d) { return d.anchor; });

  labelItems.exit().remove();

  var labelEnter = labelItems.enter()
    .append("g")
    .attr("class", "competitor-label");

  labelEnter.append("rect")
    .attr("class", "label-box-bg")
    .attr("fill", "white")
    .attr("stroke", "#ccc")
    .attr("stroke-width", 1)
    .attr("rx", 4)
    .attr("height", labelBoxHeight);

  labelEnter.append("text")
    .attr("class", "label-box-text")
    .style("font-size", labelFontSize + "px")
    .style("font-family", "sans-serif")
    .attr("text-anchor", "middle")
    .attr("dominant-baseline", "middle");

  var labelMerged = labelEnter.merge(labelItems);

  // Text sets first, so its measured width can size and center the
  // background rect under it.
  labelMerged.select("text.label-box-text")
    .text(function(d) { return d.competitor; })
    .attr("x", function(d) { return margin.left + proportionScale(d.xFrac); })
    .attr("y", labelBoxY + labelBoxHeight / 2);

  var labelMaxBoxWidth = Math.max(innerWidth - 8, 0); // 4px breathing room on each side

  labelMerged.select("rect.label-box-bg")
    .attr("y", labelBoxY)
    .attr("width", function(d) {
      // Measure the sibling text node just set above to size the box snugly,
      // but never exceed the chart's own drawable width — an overlong name
      // shouldn't be able to push the SVG's bounds outward and trigger a
      // scrollbar on the containing card.
      var textNode = d3.select(this.parentNode).select("text.label-box-text").node();
      var naturalWidth = textNode.getBBox().width + labelBoxPadding * 2;
      return Math.min(naturalWidth, labelMaxBoxWidth);
    })
    .attr("x", function(d) {
      var textNode = d3.select(this.parentNode).select("text.label-box-text").node();
      var naturalWidth = textNode.getBBox().width + labelBoxPadding * 2;
      var boxWidth = Math.min(naturalWidth, labelMaxBoxWidth);
      var idealX = margin.left + proportionScale(d.xFrac) - boxWidth / 2;
      // Clamp so the box itself never sits outside [margin.left, margin.left + innerWidth].
      return Math.max(margin.left, Math.min(idealX, margin.left + innerWidth - boxWidth));
    });

  // Note: if a competitor name is long enough that its natural width
  // exceeds labelMaxBoxWidth, the box clamps to the available width but
  // the text itself may visually extend slightly past the box edge.
  // That's a cosmetic edge case — the box never exceeds the chart's
  // bounds, which is what was causing the page-level scrollbar.

  // Text must render on top of its own box, but boxes are appended before
  // text within each <g> — raise text after sizing so it isn't hidden.
  labelMerged.select("text.label-box-text").raise();

  // ---- stacked bars: one <g> per competitor layer, rects keyed by name ----

  var layers = g.selectAll("g.layer")
    .data(series, function(d) { return d.key; });

  layers.exit().remove();

  var layersEnter = layers.enter()
    .append("g")
    .attr("class", "layer");

  var layersMerged = layersEnter.merge(layers);

  var rects = layersMerged.selectAll("rect")
    .data(
      function(d) { return d.map(function(segment) { return { segment: segment, key: d.key }; }); },
      function(d) { return d.segment.data.name; }
    );

  rects.exit()
    .transition().duration(200)
    .attr("height", 0)
    .remove();

  rects.transition().duration(700).ease(d3.easeCubicOut)
    .attr("fill", fillFor)
    .attr("y", barY)
    .attr("height", barHeight)
    .attr("x", function(d) { return proportionScale(d.segment[0]); })
    .attr("width", function(d) { return proportionScale(d.segment[1]) - proportionScale(d.segment[0]); });

  rects.enter()
    .append("rect")
    .attr("fill", fillFor)
    .attr("y", barY)
    .attr("height", barHeight)
    .attr("x", 0)
    .attr("width", 0)
    .transition().duration(700).ease(d3.easeCubicOut)
    .attr("x", function(d) { return proportionScale(d.segment[0]); })
    .attr("width", function(d) { return proportionScale(d.segment[1]) - proportionScale(d.segment[0]); });

  // ---- overall-row collapse: collapsed shows only the overall bar in a short
  // card; clicking asks Shiny to resize the card and re-render expanded, where
  // the weighted category rows cascade in below the overall bar. ----

  var allRects = layersMerged.selectAll("rect");

  var cardAnimating = false;

  allRects
    .style("cursor", function(d) {
      return d.segment.data.__overall ? "pointer" : null;
    })
    .on("click", function(event, d) {
      if (!d.segment.data.__overall || cardAnimating) return;

      var next = !expanded;
      var cardNode = svg.node().closest(".h2h-plot-card");

      function sendState() {
        if (window.Shiny && options && options.toggle_input) {
          Shiny.setInputValue(options.toggle_input, next, { priority: "event" });
        }
      }

      if (!cardNode) {
        sendState();
        return;
      }

      cardAnimating = true;

      d3.select(cardNode)
        .interrupt("card-resize")
        .style("overflow", "hidden")
        .transition("card-resize")
        .duration(900)
        .ease(d3.easeCubicInOut)
        .style("height", (next ? 700 : 200) + "px")
        .on("end", function() {
          cardAnimating = false;
          d3.select(this).style("overflow", null);
          sendState();
        });
    });

  allRects
    .style("opacity", function(d) {
      return (d.segment.data.__overall || expanded) ? 1 : 0;
    })
    .style("pointer-events", function(d) {
      return (d.segment.data.__overall || expanded) ? null : "none";
    })
    .attr("transform", function(d) {
      return (!d.segment.data.__overall && !expanded) ? "translate(0,-6)" : "translate(0,0)";
    });

  // After the card grows and the expanded plot re-renders, cascade the
  // category rows in rather than popping them into place.
  if (firstExpandedRender) {
    allRects
      .filter(function(d) { return !d.segment.data.__overall; })
      .style("opacity", 0)
      .attr("transform", "translate(0,-12)")
      .transition("reveal")
      .duration(700)
      .delay(function(d, i) { return i * 60; })
      .ease(d3.easeCubicOut)
      .style("opacity", 1)
      .attr("transform", "translate(0,0)");
  }

  svgNode.__revealState = revealState;

  // ---- per-row tooltips: hover a stacked segment to see both competitors'
  // labels side by side — the hovered segment's label on that segment's side
  // of the cursor (left segment → left, right segment → right), the other
  // competitor's on the opposite side. Tooltips anchor below the cursor
  // (grow downward) for rows in the top half of the chart and above the
  // cursor (grow upward) for rows in the bottom half. ----

  var hoveredIsTop = false;
  var hoveredIsLeft = false;
  var hoveredSize = { width: 0, height: 0 };
  var otherSize = { width: 0, height: 0 };
  var hasOther = false;

  layersMerged.selectAll("rect")
    .on("mouseover", function(event, d) {
      var labels = d.segment.data.__labels;
      var label = labels[d.key];
      if (label == null) return;

      // Horizontal bars: every segment in a row sits at the same height,
      // so cascade direction is based on the row's vertical position
      // within the plot, not stack position — rows in the top half of
      // the chart cascade down, rows in the bottom half cascade up.
      var rowCenter = categoryScale(d.segment.data.name) + categoryScale.bandwidth() / 2;
      hoveredIsTop = rowCenter < innerHeight / 2;

      // Keep each tooltip on its own segment's side: left segment → tooltip
      // to the left of the cursor, right segment → tooltip to the right.
      hoveredIsLeft = (d.segment[0] + d.segment[1]) / 2 < 0.5;

      var otherKey = Object.keys(labels).find(function(key) { return key !== d.key; });
      var otherLabel = otherKey == null ? null : labels[otherKey];

      hoveredSize = growTooltip(tooltip, label);

      if (otherLabel != null) {
        otherSize = growTooltip(tooltipOther, otherLabel);
        hasOther = true;
      } else {
        // Bye/postseason rows have only one competitor at all.
        otherSize = { width: 0, height: 0 };
        hasOther = false;
        hideTooltip(tooltipOther);
      }
    })
    .on("mousemove", function(event) {
      var viewportTop = window.scrollY;
      var viewportBottom = window.scrollY + window.innerHeight;
      var viewportLeft = window.scrollX;
      var viewportRight = window.scrollX + window.innerWidth;
      var gap = 12;

      var hoveredLeft = hoveredIsLeft
        ? event.pageX - gap - hoveredSize.width
        : event.pageX + gap;
      var hoveredTop = hoveredIsTop
        ? event.pageY + gap
        : event.pageY - gap - hoveredSize.height;

      // Clamp so the tooltip's box never extends past the viewport edges —
      // an unclamped position here is what was pushing the document's
      // bounds outward and triggering a page-level scrollbar.
      hoveredLeft = Math.max(viewportLeft, Math.min(hoveredLeft, viewportRight - hoveredSize.width));
      hoveredTop = Math.max(viewportTop, Math.min(hoveredTop, viewportBottom - hoveredSize.height));

      tooltip
        .style("left", hoveredLeft + "px")
        .style("top", hoveredTop + "px");

      if (!hasOther) return;

      var otherLeft = hoveredIsLeft
        ? event.pageX + gap
        : event.pageX - gap - otherSize.width;
      var otherTop = hoveredIsTop
        ? event.pageY + gap
        : event.pageY - gap - otherSize.height;

      otherLeft = Math.max(viewportLeft, Math.min(otherLeft, viewportRight - otherSize.width));
      otherTop = Math.max(viewportTop, Math.min(otherTop, viewportBottom - otherSize.height));

      // The two boxes sit on opposite sides of the cursor. If clamping near a
      // viewport edge makes them collide, stack the companion vertically
      // instead of flipping it onto the hovered tooltip's side.
      var overlaps = !(
        otherLeft + otherSize.width <= hoveredLeft ||
        hoveredLeft + hoveredSize.width <= otherLeft ||
        otherTop + otherSize.height <= hoveredTop ||
        hoveredTop + hoveredSize.height <= otherTop
      );

      if (overlaps) {
        var below = hoveredTop + hoveredSize.height + 8;
        var above = hoveredTop - otherSize.height - 8;
        otherTop = below + otherSize.height <= viewportBottom
          ? below
          : Math.max(viewportTop, above);
      }

      otherLeft = Math.max(viewportLeft, Math.min(otherLeft, viewportRight - otherSize.width));
      otherTop = Math.max(viewportTop, Math.min(otherTop, viewportBottom - otherSize.height));

      tooltipOther
        .style("left", otherLeft + "px")
        .style("top", otherTop + "px");
    })
    .on("mouseout", function() {
      hideTooltip(tooltip);
      hideTooltip(tooltipOther);
      hasOther = false;
    });
});

r2d3.onResize(function(width, height) {
  r2d3.svg.dispatch("render");
});