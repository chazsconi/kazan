defmodule KazanCodegenModelsTest do
  use ExUnit.Case

  alias Kazan.Codegen.Models

  describe "module_name" do
    test "returns nil when unknown name in safe mode" do
      assert Models.module_name("io.k8s.kubernetes.pkg.api.nope") == nil
    end

    test "returns a module name when in unsafe mode" do
      mod_name = Models.module_name(
        "io.k8s.kubernetes.pkg.api.yep.something", unsafe: true
      )
      assert mod_name == Kazan.Models.Api.Yep.Something
    end
  end
end
