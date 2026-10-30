This is a web application written using the Phoenix web framework.

<!-- Based on phoenixframework/phoenix main at 1e6183e9ebab9994cf6e43d3af445f32664cc10c (2026-09-04), with project-specific scope and workflow guidance. -->

## Project guidelines

- After implementation changes, run `mix precommit` once on the completed change. Fix failures caused by the change and report unrelated failures. Reuse successful checks unless subsequent changes invalidate them. For documentation-only changes, use focused document and diff checks; do not run the mutating alias for read-only reviews.
- Use the included `Req` library for HTTP requests instead of `:httpoison`, `:tesla`, or `:httpc`.

## Working guidelines

- State material assumptions. Ask when missing information changes scope, correctness, authorization, or an irreversible outcome. Resolve routine implementation choices using the existing code and user instructions.
- Continue independent authorized work while awaiting clarification. Complete the requested implementation, relevant verification, and fixes before handing it back; do not stop at a first draft unless the user requests review at that point.
- For multi-step tasks, give a brief plan with observable completion criteria. Read only the files and documentation needed for the task.
- Use the simplest implementation that meets the request. Avoid speculative features, abstractions, configurability, and unrelated refactors.
- Match existing style. Change only what the request requires; remove imports, variables, and functions made unused by your changes, and report unrelated defects without repairing them.
- Match verification to the change. Add regression coverage for behavior changes and bug fixes where it meaningfully verifies the outcome; reuse existing coverage where sufficient.
- Existing authorization does not expand task scope or execution permissions. Prepare a concrete, reviewable result before any required approval for an external or protected action.

## Phoenix component conventions

- Begin LiveView templates with `<Layouts.app flash={@flash} current_scope={@current_scope}>` to wrap their content. `Layouts` is already aliased through `BWeb`.
- Call `<.flash_group>` only inside `layouts.ex`.
- Use the imported `<.icon>` component for icons and `<.input>` for supported form inputs.
- When overriding `<.input>` classes, supply the complete styling; default classes are not inherited.

### JS and CSS guidelines

Apply these design defaults to newly created or explicitly redesigned UI. Preserve existing design during narrow fixes.

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- **Never** use `@apply` when writing raw css
- Write your own tailwind-based components instead of using daisyUI for unique, world-class design
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - Keep raw inline JavaScript out of templates; use external hooks or the supported colocated hooks described below.

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions

<!-- phoenix-gen-auth-start -->
## Authentication

- **Always** handle authentication flow at the router level with proper redirects
- **Always** be mindful of where to place routes. `phx.gen.auth` creates multiple router plugs and `live_session` scopes:
  - A plug `:fetch_current_scope_for_user` that is included in the default browser pipeline
  - A plug `:require_authenticated_user` that redirects to the log in page when the user is not authenticated
  - A `live_session :current_user` scope - for routes that need the current user but don't require authentication, similar to `:fetch_current_scope_for_user`
  - A `live_session :require_authenticated_user` scope - for routes that require authentication, similar to the plug with the same name
  - In both cases, a `@current_scope` is assigned to the Plug connection and LiveView socket
  - A plug `redirect_if_user_is_authenticated` that redirects to a default path in case the user is authenticated - useful for a registration page that should only be shown to unauthenticated users
- **Always let the user know in which router scopes, `live_session`, and pipeline you are placing the route, AND SAY WHY**
- `phx.gen.auth` assigns the `current_scope` assign - it **does not assign a `current_user` assign**
- Always pass the assign `current_scope` to context modules as first argument. When performing queries, use `current_scope.user` to filter the query results
- To derive/access `current_user` in templates, **always use the `@current_scope.user`**, never use **`@current_user`** in templates or LiveViews
- **Never** duplicate `live_session` names. A `live_session :current_user` can only be defined __once__ in the router, so all routes for the `live_session :current_user`  must be grouped in a single block
- Diagnose missing `current_scope` through the browser pipeline, mount hooks, layout assigns, and test setup. Move a route only when its existing authentication placement is incorrect; preserve the authentication requirements below.

### Routes that require authentication

LiveViews that require login should **always be placed inside the __existing__ `live_session :require_authenticated_user` block**:

    scope "/", AppWeb do
      pipe_through [:browser, :require_authenticated_user]

      live_session :require_authenticated_user,
        on_mount: [{BWeb.UserAuth, :require_authenticated}] do
        # phx.gen.auth generated routes
        live "/users/settings", UserLive.Settings, :edit
        live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
        # our own routes that require logged in user
        live "/", MyLiveThatRequiresAuth, :index
      end
    end

Controller routes must be placed in a scope that sets the `:require_authenticated_user` plug:

    scope "/", AppWeb do
      pipe_through [:browser, :require_authenticated_user]

      get "/", MyControllerThatRequiresAuth, :index
    end

### Routes that work with or without authentication

LiveViews that can work with or without authentication, **always use the __existing__ `:current_user` scope**, ie:

    scope "/", MyAppWeb do
      pipe_through [:browser]

      live_session :current_user,
        on_mount: [{BWeb.UserAuth, :mount_current_scope}] do
        # our own routes that work with or without authentication
        live "/", PublicLive
      end
    end

Controllers automatically have the `current_scope` available if they use the `:browser` pipeline.

<!-- phoenix-gen-auth-end -->

<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Use `mix help <task_name|module_name|module.function>` when the task, API, or options are unfamiliar or uncertain. Reuse documentation already checked.
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`

## Test guidelines

- Always use `start_supervised!/1` to start processes in tests as it guarantees cleanup between tests
- Avoid `Process.alive?/1` to check if a process died, use `Process.monitor/1` instead
- Avoid `Process.sleep/1` in tests, use `_ = :sys.get_state/1` to ensure the process has handled prior messages (for LiveViews, you can use `render(view)`)
<!-- phoenix:elixir-end -->

<!-- phoenix:ecto-start -->
## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programmatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct
- **Always** invoke `mix ecto.gen.migration migration_name_using_underscores` when generating migration files, so the correct timestamp and conventions are applied
<!-- phoenix:ecto-end -->

<!-- phoenix:html-start -->
## Phoenix HTML guidelines

- Always use the imported Phoenix.Component.form/1 and Phoenix.Component.inputs_for/1 functions to build forms
- **Always** add unique and stable DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `my_app_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use MyAppWeb, :html`
- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation` and interpolate using the `<%= ... %>` syntax
- Prefer to use `<%= cond do %>` in templates instead of nested if-blocks for multiple conditions
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView guidelines

- **Avoid LiveComponent's** unless you have a strong, specific need for them

- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`. Do not use `<.form let={f}`. Do not access changesets in templates

* The `to_form/2` helper can be used to convert both changesets and parameters to forms:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

- If you are using `phx-hook="MyHook"` and that JS hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute

- **Never** write raw embedded `<script>` tags in heex as they are incompatible with LiveView. Instead, use a colocated js hook script tag (`:type={Phoenix.LiveView.ColocatedHook}`), which are automatically bundled inside app.js and always start with `.`:

    <input type="text" name="user[phone_number]" id="user-phone-number" phx-hook=".PhoneNumber" />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PhoneNumber">
      export default {
        mounted() {
          this.el.addEventListener("input", e => {
            let match = this.el.value.replace(/\D/g, "").match(/^(\d{3})(\d{3})(\d{4})$/)
            if(match) {
              this.el.value = `${match[1]}-${match[2]}-${match[3]}`
            }
          })
        }
      }
    </script>

- External JS hooks (`<div id="myhook" phx-hook="MyHook">`) must be placed in `assets/js/` and passed to the LiveSocket constructor

## LiveView streams

- Prefer LiveView streams for large or incrementally updated rendered collections. Ordinary assigns are appropriate for small, bounded lists. Stream operations include:
  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: 0)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView streams are not enumerable and **do not support counting or empty states**. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

      <div id="tasks" phx-update="stream">
        <div id="tasks-empty" class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @streams.tasks} id={id}>
          {task.name}
        </div>
      </div>

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- When updating an assign that should change content inside any streamed item(s), you MUST re-stream the items along with the updated assign:

      def handle_event("edit_message", %{"message_id" => message_id}, socket) do
        scope = socket.assigns.current_scope
        message = Chat.get_message!(scope, message_id)
        edit_form = to_form(Chat.change_message(scope, message, %{content: message.content}))

        # re-insert message so @editing_message_id toggle logic takes effect for that stream item
        {:noreply,
         socket
         |> stream_insert(:messages, message)
         |> assign(:editing_message_id, String.to_integer(message_id))
         |> assign(:edit_form, edit_form)}
      end

### LiveView tests

- `Phoenix.LiveViewTest` module and `LazyHTML` (included) for making your assertions
- Keep tests focused on the changed behavior and follow the existing test-file organization; split cases when it improves clarity.
- Use stable element IDs with `element/2`, `has_element?/2`, and selectors instead of raw HTML comparisons. Assert content within those elements when it is part of the required behavior.
- Focus on testing outcomes rather than implementation details
- Be aware that `Phoenix.Component` functions like `<.form>` might produce different HTML than expected, so test against the output HTML structure
- When facing test failures with element selectors, add debug statements to print the actual HTML, but use `LazyHTML` selectors to limit the output, ie:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")
<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->
