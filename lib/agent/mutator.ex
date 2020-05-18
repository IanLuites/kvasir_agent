defmodule Kvasir.Agent.Mutator do
  def init(env) do
    Module.register_attribute(env.module, :creation, accumulate: false)
    Module.register_attribute(env.module, :event, accumulate: true)
    Module.register_attribute(env.module, :execute, accumulate: true)
    Module.register_attribute(env.module, :object_values, accumulate: true)
    Module.register_attribute(env.module, :entities, accumulate: true)
    Module.register_attribute(env.module, :setters, accumulate: true)
    Module.register_attribute(env.module, :collectors, accumulate: true)
  end

  defmacro imports do
    quote do
      import Kvasir.Agent.Mutator,
        only: [
          event: 2,
          event: 3,
          event: 4,
          event!: 2,
          event!: 3,
          event!: 4,
          execute: 2,
          execute: 3,
          execute: 4
        ]
    end
  end

  def add_object_value(env, field, type) do
    Module.put_attribute(env.module, :object_values, {field, type})
  end

  def add_setter(env, command, name, field) do
    Module.put_attribute(env.module, :setters, {command, name, field})
  end

  def add_collector(env, add, remove, name, type, opts) do
    Module.put_attribute(env.module, :collectors, {add, remove, name, type, opts})
  end

  def creation(env), do: Module.get_attribute(env.module, :creation)
  def setters(env), do: Module.get_attribute(env.module, :setters)
  def collectors(env), do: Module.get_attribute(env.module, :collectors)
  def events(env), do: Module.get_attribute(env.module, :event)
  def executes(env), do: Module.get_attribute(env.module, :execute)
  def object_values(env), do: Module.get_attribute(env.module, :object_values)
  def entities(env), do: Module.get_attribute(env.module, :entities)

  ### Event Apply Generation ###

  def gen_apply(env) do
    creation =
      if c = creation(env) do
        fields = env.module |> Module.get_attribute(:fields) |> Enum.map(&elem(&1, 0))
        {c, fields}
      end

    generate_apply(
      creation,
      events(env),
      object_values(env),
      entities(env),
      setters(env),
      collectors(env),
      []
    )
  end

  def generate_apply(creation, events, object_values, entities, setters, collectors, path \\ []) do
    base =
      Enum.reduce(
        object_values,
        nil,
        fn {field, v}, acc ->
          quote do
            unquote(acc)
            unquote(v.generate_apply([field | path]))
          end
        end
      )

    apply =
      Enum.reduce(
        events,
        base,
        &quote do
          unquote(generate_apply_rule(&1, path))
          unquote(&2)
        end
      )

    forwards =
      Enum.reduce(
        entities,
        apply,
        &quote do
          unquote(generate_apply_forward(&1))
          unquote(&2)
        end
      )

    set =
      Enum.reduce(
        setters,
        forwards,
        &quote do
          unquote(&2)
          unquote(generate_apply_set(&1, path))
        end
      )

    collect =
      Enum.reduce(
        collectors,
        set,
        &quote do
          unquote(&2)
          unquote(generate_apply_collect(&1, path))
        end
      )

    quote do
      unquote(generate_apply_creation(creation))
      unquote(collect)
    end
  end

  defp generate_apply_collect({add, remove, name, type, opts}, path) do
    p = if(name, do: [name | path], else: path)

    field =
      opts[:field] ||
        Enum.find_value(add.__command__(:fields), fn {a, _, _} ->
          if String.starts_with?("#{name}", "#{a}"), do: a
        end)

    [add_e] = add.__command__(:emits)
    [remove_e] = remove.__command__(:emits)

    {add_body, remove_body} =
      case {type, opts[:unique]} do
        {:map, unique} ->
          {quote do
             {:ok, Map.put(current, unquote(unique).(to_add), to_add)}
           end,
           quote do
             {:ok, Map.delete(current, unquote(unique).(to_remove))}
           end}

        {:list, _} ->
          {quote do
             {:ok, [to_add | current]}
           end,
           quote do
             {:ok, Enum.filter(current, &(&1 != to_remove))}
           end}
      end

    add =
      generate_apply_rule(
        {
          quote(do: %unquote(add_e){unquote(field) => to_add}),
          quote(do: current),
          add_body,
          [guard: nil]
        },
        p
      )

    remove =
      generate_apply_rule(
        {
          quote(do: %unquote(remove_e){unquote(field) => to_remove}),
          quote(do: current),
          remove_body,
          [guard: nil]
        },
        p
      )

    quote do
      unquote(add)
      unquote(remove)
    end
  end

  defp generate_apply_set({command, name, field}, path) do
    [event] = command.__command__(:emits)

    generate_apply_rule(
      {
        {:%, [], [event, {:%{}, [], [{field, {:a, [], Elixir}}]}]},
        {:state, [], Elixir},
        {:ok, {:%{}, [], [{:|, [], [{:state, [], Elixir}, [{name, {:a, [], Elixir}}]]}]}},
        [guard: nil]
      },
      path
    )
  end

  defp generate_apply_creation(nil), do: nil

  defp generate_apply_creation({{command, _}, mutator_fields}) do
    fields =
      :fields
      |> command.__command__()
      |> Enum.map(&elem(&1, 0))
      |> Enum.filter(&(&1 in mutator_fields))

    created_fields = Enum.map(fields, &{&1, {&1, [], Elixir}})
    event = {:%, [], [List.first(command.__command__(:emits)), {:%{}, [], created_fields}]}
    created = {:%, [], [{:__MODULE__, [], Elixir}, {:%{}, [], created_fields}]}

    quote do
      def apply(nil, unquote(event)), do: {:ok, unquote(created)}
    end
  end

  defp generate_apply_rule({event, state, block, opts}, path) do
    event = with {:__aliases__, _, _} <- event, do: {:%, [], [event, {:%{}, [], []}]}

    if path == [] do
      if g = opts[:guard] do
        quote do
          def apply(unquote(state), unquote(event)) when unquote(g) do
            unquote(block)
          end
        end
      else
        quote do
          def apply(unquote(state), unquote(event)) do
            unquote(block)
          end
        end
      end
    else
      vars = Enum.map(1..Enum.count(path), &{:"mutator#{&1}", [], nil})

      match =
        path
        |> Enum.zip(vars)
        |> Enum.reduce(state, fn {p, v}, acc ->
          {:=, [], [v, {:%{}, [], [{p, acc}]}]}
        end)

      update =
        path
        |> Enum.zip(vars)
        |> Enum.reduce({:mutator0, [], nil}, fn {p, v}, acc ->
          {:%{}, [], [{:|, [], [v, [{p, acc}]]}]}
        end)

      if g = opts[:guard] do
        quote do
          def apply(unquote(match), unquote(event)) when unquote(g) do
            with {:ok, unquote({:mutator0, [], nil})} <- unquote(block),
                 do: {:ok, unquote(update)}
          end
        end
      else
        quote do
          def apply(unquote(match), unquote(event)) do
            with {:ok, unquote({:mutator0, [], nil})} <- unquote(block),
                 do: {:ok, unquote(update)}
          end
        end
      end
    end
  end

  defp generate_apply_forward({name, entity}) do
    match =
      {:=, [],
       [
         {:state, [], Kvasir.Agent.Mutator},
         {:%{}, [], [{name, {:entities, [], Kvasir.Agent.Mutator}}]}
       ]}

    quote do
      def apply(
            unquote(match),
            event = %{__meta__: meta = %{sub_key: [{unquote(name), id} | path]}}
          ) do
        e = %{event | __meta__: %{meta | sub_key: path}}

        current =
          case Map.fetch(entities, id) do
            {:ok, s} -> s
            :error -> unquote(entity).base(id)
          end

        with {:ok, new} <- unquote(entity).apply(current, e) do
          {:ok, %{state | unquote(name) => Map.put(entities, id, new)}}
        end
      end
    end
  end

  ### Execution Generation ###

  def gen_exec(env) do
    generate_execution(
      creation(env),
      executes(env),
      object_values(env),
      entities(env),
      setters(env),
      collectors(env),
      []
    )
  end

  def generate_execution(
        creation,
        executes,
        object_values,
        entities,
        setters,
        collectors,
        path \\ []
      ) do
    base =
      Enum.reduce(
        object_values,
        nil,
        fn {field, v}, acc ->
          quote do
            unquote(acc)
            unquote(v.generate_execution([field | path]))
          end
        end
      )

    exec =
      Enum.reduce(
        executes,
        base,
        &quote do
          unquote(generate_execute(&1, path))
          unquote(&2)
        end
      )

    forwards =
      Enum.reduce(
        entities,
        exec,
        &quote do
          unquote(generate_execute_forward(&1))
          unquote(&2)
        end
      )

    set =
      Enum.reduce(
        setters,
        forwards,
        &quote do
          unquote(&2)
          unquote(generate_execute_set(&1, path))
        end
      )

    collect =
      Enum.reduce(
        collectors,
        set,
        &quote do
          unquote(&2)
          unquote(generate_execute_collect(&1, path))
        end
      )

    quote do
      unquote(generate_execute_creation(creation))
      unquote(collect)
    end
  end

  defp generate_execute_collect({add, remove, name, type, opts}, path) do
    p = if(name, do: [name | path], else: path)

    field =
      opts[:field] ||
        Enum.find_value(add.__command__(:fields), fn {a, _, _} ->
          if String.starts_with?("#{name}", "#{a}"), do: a
        end)

    {add_body, remove_body} =
      case {type, opts[:unique]} do
        {:map, unique} ->
          {quote do
             if Map.has_key?(current, unquote(unique).(to_add)),
               do: {:error, unquote(:"#{field}_already_added")},
               else: unquote(add).to_event(c)
           end,
           quote do
             if Map.has_key?(current, unquote(unique).(to_remove)),
               do: unquote(remove).to_event(c),
               else: {:error, unquote(:"#{field}_not_added")}
           end}

        {:list, _} ->
          {quote do
             if to_add in current,
               do: {:error, unquote(:"#{field}_already_added")},
               else: unquote(add).to_event(c)
           end,
           quote do
             if to_remove in current,
               do: unquote(remove).to_event(c),
               else: {:error, unquote(:"#{field}_not_added")}
           end}
      end

    add =
      generate_execute(
        {
          quote(do: c = %unquote(add){unquote(field) => to_add}),
          quote(do: current),
          add_body,
          [guard: nil]
        },
        p
      )

    remove =
      generate_execute(
        {
          quote(do: c = %unquote(remove){unquote(field) => to_remove}),
          quote(do: current),
          remove_body,
          [guard: nil]
        },
        p
      )

    quote do
      unquote(add)
      unquote(remove)
    end
  end

  defp generate_execute_set({command, name, field}, path) do
    generate_execute(
      {
        quote(do: c = %unquote(command){unquote(field) => new}),
        quote(do: %{unquote(name) => current}),
        quote do
          if new == current,
            do: {:error, unquote(:"#{name}_already_set")},
            else: unquote(command).to_event(c)
        end,
        [guard: nil]
      },
      path
    )
  end

  defp generate_execute_creation(nil), do: nil

  defp generate_execute_creation({command, opts}) do
    tag = if(t = opts[:tag], do: "#{t}_", else: "")
    cmd = {:%, [], [command, {:%{}, [], []}]}

    exec =
      if v = opts[:validate] do
        quote do
          def execute(nil, c = unquote(cmd)) do
            with :ok <- unquote(v).(c), do: unquote(command).to_event(c)
          end
        end
      else
        quote do
          def execute(nil, c = unquote(cmd)), do: unquote(command).to_event(c)
        end
      end

    quote do
      unquote(exec)
      def execute(_, unquote(cmd)), do: {:error, unquote(:"#{tag}already_exists")}
      def execute(nil, _), do: {:error, unquote(:"#{tag}does_not_exist")}
    end
  end

  defp generate_execute_forward({name, entity}) do
    match = {:%{}, [], [{name, {:entities, [], Kvasir.Agent.Mutator}}]}

    quote do
      def execute(
            unquote(match),
            cmd = %{__meta__: meta = %{entity: sub_key = [{unquote(name), id} | _path]}}
          ) do
        state =
          case Map.fetch(entities, id) do
            {:ok, e} -> e
            :error -> unquote(entity).base(id)
          end

        case unquote(entity).execute(state, cmd) do
          {:ok, e = %{__meta__: m}} ->
            {:ok, %{e | __meta__: %{m | sub_key: sub_key}}}

          {:ok, es} ->
            {:ok,
             Enum.map(es, fn e = %{__meta__: m} -> %{e | __meta__: %{m | sub_key: sub_key}} end)}

          err ->
            err
        end
      end
    end
  end

  defp generate_execute({command, state, block, opts}, path) do
    match = Enum.reduce(path, state, fn p, acc -> {:%{}, [], [{p, acc}]} end)
    cmd = with {:__aliases__, _, _} <- command, do: {:%, [], [command, {:%{}, [], []}]}

    if g = opts[:guard] do
      quote do
        def execute(unquote(match), unquote(cmd)) when unquote(g) do
          unquote(block)
        end
      end
    else
      quote do
        def execute(unquote(match), unquote(cmd)) do
          unquote(block)
        end
      end
    end
  end

  defp add_event(env, event, state, block, opts) do
    {event, a} = de_alias(event, env)
    {block, b} = de_alias(block, env)

    {s, g} =
      case state do
        {:when, _, [s, w]} -> {s, w}
        _ -> {state, nil}
      end

    Module.put_attribute(env.module, :event, {event, s, block, Keyword.put(opts, :guard, g)})

    Enum.reduce(
      a ++ b,
      nil,
      &quote do
        unquote(&2)
        _ = unquote(&1)
      end
    )
  end

  defp add_execute(env, command, state, block, opts) do
    {command, a} = de_alias(command, env)
    {block, b} = de_alias(block, env)

    {s, g} =
      case state do
        {:when, _, [s, w]} -> {s, w}
        _ -> {state, nil}
      end

    Module.put_attribute(env.module, :execute, {command, s, block, Keyword.put(opts, :guard, g)})

    Enum.reduce(
      a ++ b,
      nil,
      &quote do
        unquote(&2)
        _ = unquote(&1)
      end
    )
  end

  defp de_alias(block, env) do
    Macro.traverse(
      block,
      [],
      fn node, acc -> {node, acc} end,
      fn
        c = {:__aliases__, o, x}, acc ->
          expanded = c |> Macro.expand(env) |> Module.split() |> Enum.map(&String.to_atom/1)

          if expanded == x do
            {c, acc}
          else
            {{:__aliases__, o, [:"Elixir" | expanded]}, [c | acc]}
          end

        node, acc ->
          {node, acc}
      end
    )
  end

  defmacro event!(event, do: block) do
    add_event(__CALLER__, event, {:_, [], nil}, {:ok, block}, [])
  end

  defmacro event!(event, state_or_opts, do: block) do
    if is_list(state_or_opts) do
      add_event(
        __CALLER__,
        event,
        {:_, [], nil},
        {:ok, block},
        state_or_opts
      )
    else
      add_event(__CALLER__, event, state_or_opts, {:ok, block}, [])
    end
  end

  defmacro event!(event, state, opts, block) do
    add_event(__CALLER__, event, state, {:ok, block}, opts)
  end

  defmacro event(event, do: block) do
    add_event(__CALLER__, event, {:_, [], nil}, block, [])
  end

  defmacro event(event, state_or_opts, do: block) do
    if is_list(state_or_opts) do
      add_event(
        __CALLER__,
        event,
        {:_, [], nil},
        block,
        state_or_opts
      )
    else
      add_event(__CALLER__, event, state_or_opts, block, [])
    end
  end

  defmacro event(event, state, opts, block) do
    add_event(__CALLER__, event, state, block, opts)
  end

  defmacro execute(command, do: block) do
    add_execute(__CALLER__, command, {:_, [], nil}, block, [])
  end

  defmacro execute(command, state_or_opts, do: block) do
    if is_list(state_or_opts) and state_or_opts != [] do
      add_execute(
        __CALLER__,
        command,
        {:_, [], nil},
        block,
        state_or_opts
      )
    else
      add_execute(__CALLER__, command, state_or_opts, block, [])
    end
  end

  defmacro execute(command, state, opts, block) do
    add_execute(__CALLER__, command, state, block, opts)
  end
end
