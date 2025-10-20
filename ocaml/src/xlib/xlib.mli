(** @author Davy Cottet

    A library of helper functions automatically opened in the `xeus-ocaml`
    toplevel. It provides a simple API for users to generate and display rich
    outputs (like HTML, Markdown, and plots) in their Jupyter notebooks. *)

val get_and_clear_outputs : unit -> Protocol.output list
(** Internal function for the toplevel to retrieve and clear all pending rich
    outputs generated during the last code execution. This is not intended for
    direct use by end-users.
    @return A list of {!Protocol.output} values in the order they were created.
*)

val output_display_data : Yojson.Safe.t -> unit
(** Renders a full MIME bundle as a cell output. This is the most flexible
    function for creating rich output with multiple representations.
    @param data A Yojson object representing the MIME bundle. *)

val output_html : string -> unit
(** Renders a raw HTML string as a cell output. The frontend will interpret and
    display the HTML content.
    @param s The HTML content as a string. *)

val output_markdown : string -> unit
(** Renders a raw Markdown string as a cell output. The frontend will interpret
    and display the formatted Markdown.
    @param s The Markdown content as a string. *)

val output_latex : string -> unit
(**
  Renders a raw LaTeX string as a cell output, typically for displaying
  mathematical equations.
  @param s The LaTeX content as a string (e.g., "$$ e^{i\pi} + 1 = 0 $$").
 *)

val output_svg : string -> unit
(** Renders an SVG image from its XML string representation.
    @param s A string containing the full `<svg>...</svg>` XML markup. *)

val output_json : string -> unit
(** Renders a JSON string as a collapsible, interactive tree view in the output.
    This function parses the input string; if parsing fails, an error message is
    sent to stderr instead of producing an output.
    @param s A string containing valid JSON. *)

val output_png_base64 : string -> unit
(** Displays a PNG image from a Base64-encoded string.
    @param s The Base64-encoded string of the PNG image data. *)

val output_jpeg_base64 : string -> unit
(** Displays a JPEG image from a Base64-encoded string.
    @param s The Base64-encoded string of the JPEG image data. *)

val output_gif_base64 : string -> unit
(** Displays a GIF image from a Base64-encoded string.
    @param s The Base64-encoded string of the GIF image data. *)

val output_pdf_base64 : string -> unit
(** Renders an inline PDF document from a Base64-encoded string. The frontend
    may embed a PDF viewer directly in the cell output.
    @param s The Base64-encoded string of the PDF file data. *)

val output_vegalite : string -> unit
(** Renders an interactive Vega-Lite plot from its JSON specification. This
    function parses the input string; if parsing fails, an error message is sent
    to stderr instead.
    @param s A string containing a valid Vega-Lite JSON specification. *)

val output_vega : string -> unit
(** Renders an interactive Vega plot from its JSON specification. This function
    parses the input string; if parsing fails, an error message is sent to
    stderr instead.
    @param s A string containing a valid Vega JSON specification. *)

val output_dot : string -> unit
(** Outputs a Graphviz dot string with the custom MIME type for rendering by a
    frontend extension.
    @param s A string containing a valid Graphviz dot specification. *)
