# QUEST: Code Context

## Purpose
The purpose of this initiative is to establish a unified framework that automates and structures the generation of information about source code and architecture in a monorepo. The main motivation is to ensure that a Large Language Model (LLM) has sufficient context—covering code, architecture, and technical descriptions—to make well-informed decisions about architecture and implementation. This project also aims to facilitate future code maintenance by providing clear access to core functionality and underlying technologies.
 - Need for a comprehensive overview of the monorepo’s file structure and functions.  
  - Desire to use an LLM effectively for architecture decisions.  
  - Ensuring consistent docstrings and “Goal” descriptions across Python and JavaScript/TypeScript code.
  - Automate the collection of code information (including function names, purpose, architecture, and infrastructure components).  
  - Generate Markdown suitable for an LLM.  

## Expected Output  
  - A robust, script-based setup that:  
    1. Gathers code context for each service to be used as context for an LLM to help it generate excellent code.  
    2. Creates an architecture document based on discovered technologies.  
  - Enhanced collaboration between developers and the LLM, allowing more informed architectural and code decisions.

## Expected Outcome
  - Improvements in LLM generated code, so that
    - 100% of LLM generated code is related to the quests
    - 100% of LLM generated code is coherent with values and principles
    - 100% of LLM generated code is coherent with the architecture

## Team
    - **Eystein T Kleivenes**: Responsible for code implementation.  
