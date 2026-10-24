# Shared Examples for MCP Tools

This directory contains reusable test patterns for cov-loupe MCP tools.

## File-Based MCP Tools

The `file_based_mcp_tools.rb` shared example provides parameterized testing for MCP tools that follow the same pattern:

- Take a `path` parameter (file to analyze)
- Call a specific method on `CoverageModel`
- Return JSON text payloads with predictable structure

### Usage

Instead of creating separate spec files for each similar tool, add your tool to the `FILE_BASED_TOOL_CONFIGS` hash:

```ruby
# In spec/cov_loupe/shared_examples/file_based_mcp_tools.rb
your_tool: {
  tool_class: CovLoupe::Tools::YourTool,
  model_method: :your_method,
  expected_keys: ['file', 'your_data'],
  description: 'your tool data',
  mock_data: {
    'file' => '/abs/path/lib/foo.rb',
    'your_data' => { 'key' => 'value' }
  },
  additional_validations: ->(data, item) {
    expect(data['your_data']).to include('key')
  }
}
```

The parameterized test will automatically:
- ✅ Test basic MCP text response structure
- ✅ Verify expected JSON keys are present
- ✅ Run tool-specific validations
- ✅ Test parameter consistency across tools
- ✅ Validate JSON structure consistency

### Benefits vs Individual Spec Files

#### Before (Individual Files)
```ruby
# spec/your_tool_spec.rb - 25+ lines
RSpec.describe CovLoupe::Tools::YourTool do
  let(:server_context) { null_server_context }
  
  before do
    setup_mcp_response_stub
    model = instance_double(CovLoupe::CoverageModel)
    allow(CovLoupe::CoverageModel).to receive(:new).and_return(model)
    allow(model).to receive(:your_method).with('lib/foo.rb').and_return({
      'file' => '/abs/path/lib/foo.rb',
      'your_data' => { 'key' => 'value' }
    })
  end

  subject { described_class.call(path: 'lib/foo.rb', server_context: server_context) }

  it_behaves_like 'an MCP tool that returns text JSON'

  it 'returns your tool data with expected structure' do
    response = subject
    data, item = expect_mcp_text_json(response, expected_keys: ['file', 'your_data'])
    expect(data['your_data']).to include('key')
  end
end
```

#### After (Parameterized)
```ruby
# Just add to FILE_BASED_TOOL_CONFIGS - 8 lines
your_tool: {
  tool_class: CovLoupe::Tools::YourTool,
  model_method: :your_method,
  expected_keys: ['file', 'your_data'], 
  description: 'your tool data',
  mock_data: { 'file' => '/abs/path/lib/foo.rb', 'your_data' => { 'key' => 'value' } },
  additional_validations: ->(data, item) { expect(data['your_data']).to include('key') }
}
```

### Additional Benefits

1. **Cross-tool consistency testing**: Automatically tests that all tools handle parameters consistently
2. **Structural validation**: Ensures all tools return properly formed MCP text responses
3. **Reduced maintenance**: Bug fixes and improvements benefit all tools at once
4. **Better coverage**: Gets consistency tests you wouldn't write individually
5. **Enforces patterns**: Encourages consistent tool design

### When NOT to Use This

Don't use the parameterized approach for tools that:
- Don't follow the file-based pattern (e.g., `ProjectCoverageTool`, `VersionTool`)
- Have significantly different parameter signatures
- Need extensive tool-specific testing that doesn't fit the pattern
- Are prototypes or experimental tools

For these cases, create individual spec files as needed.

### Current Tools Using This Pattern

- ✅ `FileCoverageSummaryTool` - File summary data
- ✅ `FileCoverageRawTool` - Raw coverage arrays
- ✅ `FileUncoveredLinesTool` - Uncovered line numbers
- ✅ `FileCoverageDetailedTool` - Line-by-line coverage details

All four tools run the shared examples plus their tool-specific tests.
