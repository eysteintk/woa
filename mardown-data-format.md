# Markdown Data Format & Graph Structure Specification

**Metadata**:
Version: 2.0
Created: 2025-01-30
Author: System
Type: Core Specification

## Required Response Format

Every LLM response MUST:

1. **Structure Data as Valid Markdown**
   - Must render properly in any Markdown viewer
   - Must contain machine-extractable data
   - Must preserve all context and explanations
   - Must use natural Markdown formatting

2. **Include Complete Implementation**
   - Always provide complete code files
   - Use language-tagged code blocks
   - Never show partial code snippets
   - Include all necessary context

3. **Follow Exact Formatting**
   - Use proper heading hierarchy (# ## ###)
   - Apply consistent bold labels for data blocks
   - Include metadata blocks where relevant
   - Format references using [[doc:name:version:section:title]]

## 1. Core Principles

1. **Readable Markdown**  
   - Everything renders properly in standard Markdown viewers
   - Content remains human-readable
   - Structure is visually clear
   - Format feels natural for both humans and machines

2. **Section-Based Organization**  
   - Each top-level heading is a discrete "section"
   - Sections can be stored and retrieved independently
   - Sections reassemble into complete documents
   - Hierarchy is preserved in storage

3. **Complete Code Blocks**  
   - Every code block is a complete, valid file
   - All code includes proper language tags
   - Includes necessary comments and documentation
   - Ready for direct execution/deployment

4. **Graph-Based Linking**  
   - References use consistent [[double-bracket]] syntax
   - Links connect related content across documents
   - Creates a knowledge graph structure
   - Enables content discovery and navigation

## 2. Data Structure Elements

### 2.1 Basic Data Types

**Text Values**:  
Simple: Plain text value  
Formatted: **bold text** or *italic text*  
Null: ~~undefined value~~  
Multi-line: Text that spans
           multiple lines  

**Boolean Values**:  
True: [x] Enabled feature  
False: [ ] Disabled feature  

**Numeric Values**:  
Integer: 42  
Float: 3.14159  
Currency: $19.99  
Range: 1..100  

**Date/Time Values**:  
Date: 2025-01-30  
Time: 15:45:00  
Timestamp: 2025-01-30T15:45:00Z  

### 2.2 Collections

**Ordered Lists**:
1. First item
2. Second item
   1. Nested item A
   2. Nested item B
3. Third item

**Unordered Lists**:
- Major item
  - Sub-item one
  - Sub-item two
    - Deep nested item
- Another major item

**Key-Value Maps**:  
Name: John Doe  
Age: 30  
Active: [x]  
Roles:  
  - Admin  
  - User  

### 2.3 Complex Structures

**Tables**:
| Column 1 | Column 2 | Column 3 |
|----------|----------|----------|
| Value 1  | Value 2  | Value 3  |
| Data A   | Data B   | Data C   |

**Nested Objects**:  
**User**:  
  Name: Alice  
  **Address**:  
    Street: 123 Main St  
    City: Springfield  
  **Settings**:  
    Theme: Dark  
    Notifications: [x]  

### 2.4 Code & Documentation

**Implementation Example**:
```python
class DataProcessor:
    """
    Processes structured Markdown data.
    
    Attributes:
        source (str): Source document path
        version (str): Document version
    """
    
    def __init__(self, source: str, version: str = "1.0"):
        self.source = source
        self.version = version
        self._sections = {}
        
    def process_section(self, section_name: str) -> dict:
        """
        Process a named section into structured data.
        
        Args:
            section_name: Name of section to process
            
        Returns:
            dict: Structured data from section
        """
        # Implementation
        pass
```

> **Implementation Notes**:
> - Class handles Markdown parsing
> - Preserves document structure
> - Maintains section hierarchy
> - Extracts structured data

### 2.5 References & Links

**Internal References**:
- Section link: [[doc:current:v1:section:implementation]]
- Full document: [[doc:specification:v2:full]]

**External References**:
- API Docs: [[doc:api:v1:section:endpoints]]
- Schema: [[doc:schema:v2:section:types]]

## 3. Complete Document Example

```markdown
# User Authentication Service

**Metadata**:
Version: 2.0
Created: 2025-01-30
Author: System
Status: [x] Active

## Service Configuration

**Environment**:  
Name: Production  
Region: US-West  
Replicas: 3  

**Dependencies**:
- Redis 7.0+
- Python 3.11+
- Nginx 1.24+

## Implementation

```python
from datetime import datetime
from typing import Optional, Dict

class AuthService:
    """
    Handles user authentication and session management.
    """
    
    def __init__(self, config: Dict[str, any]):
        self.config = config
        self._initialized_at = datetime.utcnow()
        
    async def authenticate(
        self,
        username: str,
        password: str
    ) -> Optional[str]:
        """
        Authenticates user and returns session token.
        
        Args:
            username: User's login name
            password: User's password
            
        Returns:
            Optional[str]: Session token if successful
        """
        # Implementation
        pass
```

**Access Matrix**:
| Role    | Read | Write | Admin |
|---------|------|-------|-------|
| User    | [x]  | [ ]   | [ ]   |
| Manager | [x]  | [x]   | [ ]   |
| Admin   | [x]  | [x]   | [x]   |

**References**:
- [[doc:auth:v2:section:security]]
- [[doc:api:v1:section:endpoints]]
```

## 4. Storage Implementation

### 4.1 Redis Key Structure

**Document Keys**:
```
doc:{name}:{version} -> Hash
  .title    -> string
  .author   -> string
  .created  -> timestamp
  .sections -> list
```

**Section Keys**:
```
doc:{name}:{version}:section:{id} -> Hash
  .content    -> string (markdown)
  .metadata   -> hash
  .references -> set
```

**Reference Tracking**:
```
refs:{doc}:{version}:section:{id} -> Set
  -> [[ref1]]
  -> [[ref2]]
```

### 4.2 Version Control

**Version Keys**:
```
versions:{doc} -> Sorted Set
  score:  timestamp
  member: version_id
```

## 5. Usage Guidelines

1. **Document Creation**
   - Start with metadata block
   - Use clear section hierarchy
   - Include all required data types
   - Add contextual documentation

2. **Code Integration**
   - Provide complete implementations
   - Include type hints and docstrings
   - Add usage examples
   - Document dependencies

3. **Reference Management**
   - Use consistent reference format
   - Include version numbers
   - Reference specific sections
   - Maintain link validity

4. **Data Validation**
   - Ensure Markdown validity
   - Verify code completeness
   - Check reference integrity
   - Validate data types

**References**:
- [[doc:format:v1:section:types]]
- [[doc:schema:v2:section:validation]]
- [[doc:code:v1:section:standards]]

